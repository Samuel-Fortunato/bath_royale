"""Versioned application-owned release service, JSON request on stdin.

Manager owns presentation/custody. Existing build, certificate, APK and draft
publication tools remain the implementation authorities. No credentials returned.
"""

import contextlib
import fcntl
import hashlib
import io
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from app_version import ROOT, bump, current, metadata
from build_alpha import configuration, verify_distribution_payload
from release_ledger import Ledger, digest, gh
from verify_preview import CERTIFICATE, private_file, verify_apk, verify_key

PROTOCOL = 1
REQUIRED_WORKFLOWS = ("android-preview.yml", "backend-administration.yml")


def run(*args, timeout=3600, env=None):
    process = subprocess.Popen(
        list(map(str, args)),
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except BaseException:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise
    if process.returncode:
        raise ValueError(
            "Ferramenta falhou; diagnósticos privados omitidos. Consulta CI ou os pré-requisitos."
        )
    return output.strip()


def source(*, strict=False):
    if strict:
        run("git", "fetch", "--quiet", "origin")
    sha = run("git", "rev-parse", "HEAD")
    dirty = bool(run("git", "status", "--porcelain"))
    counts = run(
        "git", "rev-list", "--left-right", "--count", "HEAD...@{upstream}"
    ).split()
    ahead, behind = map(int, counts)
    if strict and (dirty or ahead or behind):
        raise ValueError(
            "A origem exige árvore limpa e commit igual ao upstream após fetch."
        )
    return {"source": sha, "dirty": dirty, "ahead": ahead, "behind": behind}


def api(repo, path):
    return json.loads(gh("api", f"repos/{repo}/{path}"))


def ci_required(repo, sha):
    observations = []
    for workflow in REQUIRED_WORKFLOWS:
        runs = api(
            repo, f"actions/workflows/{workflow}/runs?head_sha={sha}&per_page=100"
        )["workflow_runs"]
        runs = [
            r
            for r in runs
            if r["head_sha"] == sha and r["event"] in ("push", "workflow_dispatch")
        ]
        latest = (
            max(runs, key=lambda r: (r["run_number"], r["run_attempt"]))
            if runs
            else None
        )
        if (
            not latest
            or latest["status"] != "completed"
            or latest["conclusion"] != "success"
        ):
            raise ValueError(
                "CI obrigatória ausente, pendente ou sem sucesso para o commit exato."
            )
        observations.append(
            {
                "workflow": workflow,
                "run": latest["id"],
                "attempt": latest["run_attempt"],
            }
        )
    return observations


def safe_directory(path, create=False):
    path = Path(path).absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("Não são permitidas ligações simbólicas nos artefactos.")
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError(
            "A pasta de artefactos exige modo 0700 e o proprietário atual."
        )
    return path


def checksum(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def public_config(value):
    # Accept the application's existing api.json naming without accepting secrets.
    return configuration(
        value.get("SUPABASE_URL", value.get("url", "")),
        value.get("SUPABASE_PUBLISHABLE_KEY", value.get("publishable_key", "")),
    )


def verify_record(directory):
    directory = safe_directory(directory)
    record = json.loads(private_file(directory / "release.json").read_text())
    source_text = None
    if record["channel"] == "candidate":
        if not re.fullmatch(r"[a-f0-9]{40}", record["source"]):
            raise ValueError("Commit do artefacto inválido.")
        source_text = run("git", "show", record["source"] + ":pubspec.yaml")
    info = metadata(record["channel"], record["version_code"], pubspec_text=source_text)
    if any(info[k] != record[k] for k in ("version", "version_name", "package")):
        raise ValueError(
            "O artefacto não corresponde à versão/canal atual; usa a origem exata."
        )
    apk = private_file(directory / "bath-royale.apk")
    expected = checksum(apk) + "  ./bath-royale.apk\n"
    if (directory / "SHA256SUMS").read_text() != expected or checksum(apk) != record[
        "sha256"
    ]:
        raise ValueError("Checksum APK divergente; não instalar nem publicar.")
    with contextlib.redirect_stdout(io.StringIO()):
        verify_apk(
            str(apk), str(info["version_code"]), info["version_name"], info["package"]
        )
    if record["channel"] != "development":
        verify_distribution_payload(apk)
    return record


@contextlib.contextmanager
def build_lock(directory):
    base = safe_directory(Path(directory).parent)
    fd = os.open(base / ".build.lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError(
                "Outra compilação está ativa; repete o mesmo pedido após terminar."
            ) from None
        yield
    finally:
        os.close(fd)


def build(request):
    with build_lock(request["directory"]):
        return build_locked(request)


def build_locked(request):
    channel = request["channel"]
    if channel not in ("development", "candidate"):
        raise ValueError(
            "Seleciona development ou candidate; alpha é apenas publicação aprovada."
        )
    state = source(strict=channel == "candidate")
    directory = safe_directory(request["directory"], create=True)
    if (directory / "release.json").exists():
        record = verify_record(directory)
        if record["source"] != state["source"] or record["channel"] != channel:
            raise ValueError("Pedido já vinculado a outra origem/canal.")
        return record
    allocation = (
        Ledger(request["repo"]).allocate(
            request["request"],
            state["source"],
            current(),
            minimum=request.get("minimum", 0),
        )
        if channel == "candidate"
        else None
    )
    info = metadata(channel, allocation["code"] if allocation else 1)
    key = private_file(request["keystore"])
    signing_path = private_file(request["signing_config"])
    signing_config = json.loads(signing_path.read_bytes())
    if set(signing_config) != {"alias", "store_password", "key_password"} or not all(
        isinstance(v, str) and v for v in signing_config.values()
    ):
        raise ValueError("O formato da configuração de assinatura diverge.")
    with tempfile.TemporaryDirectory(prefix="bath-signing-") as temporary:
        password = Path(temporary) / "password"
        fd = os.open(password, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write(signing_config["store_password"])
        verify_key(key, password)
    del signing_config
    env = dict(
        os.environ,
        PREVIEW_KEYSTORE=str(key),
        PREVIEW_SIGNING_CONFIG=str(signing_path),
        BATH_BUILD_CHANNEL=channel,
    )
    run("flutter", "pub", "get", "--enforce-lockfile", env=env)
    if channel == "candidate":
        config = public_config(request["public_config"])
        env.update(
            ALPHA_RELEASE_APPROVED="true",
            SUPABASE_URL=config["SUPABASE_URL"],
            SUPABASE_PUBLISHABLE_KEY=config["SUPABASE_PUBLISHABLE_KEY"],
        )
        run(
            sys.executable,
            "tool/build_alpha.py",
            "--number",
            info["version_code"],
            env=env,
        )
    else:
        config = {}
        run(
            "flutter",
            "build",
            "apk",
            "--release",
            "--no-pub",
            "--build-name",
            info["version_name"],
            "--build-number",
            1,
            "--dart-define=BATH_APP_VERSION=" + info["version_name"],
            env=env,
        )
    # A build must not silently bind a changed source tree/configuration.
    if source()["source"] != state["source"] or (
        channel == "candidate" and source()["dirty"]
    ):
        raise ValueError("Origem alterada durante a compilação; artefacto recusado.")
    apk = directory / "bath-royale.apk"
    shutil.copyfile(ROOT / "build/app/outputs/flutter-apk/app-release.apk", apk)
    apk.chmod(0o600)
    with contextlib.redirect_stdout(io.StringIO()):
        verify_apk(
            str(apk), str(info["version_code"]), info["version_name"], info["package"]
        )
    notes = (ROOT / "docs/releases/alpha-notes.md").read_bytes()
    (directory / "notes.md").write_bytes(notes)
    (directory / "notes.md").chmod(0o600)
    record = dict(
        info,
        **state,
        allocation=allocation,
        sha256=checksum(apk),
        certificate=CERTIFICATE,
        config_hash=digest(config),
        notes_hash=checksum(directory / "notes.md"),
    )
    (directory / "SHA256SUMS").write_text(record["sha256"] + "  ./bath-royale.apk\n")
    (directory / "SHA256SUMS").chmod(0o600)
    (directory / "release.json").write_text(json.dumps(record, indent=2))
    (directory / "release.json").chmod(0o600)
    return record


def install(directory, repo=None):
    record = (
        verify_record(directory)
        if repo is None or (Path(directory) / "release.json").exists()
        else verify_public(directory, repo)
    )
    if record["channel"] not in ("candidate", "alpha"):
        raise ValueError("A instalação gerida exige candidate sem fixtures.")
    package = record["package"]
    run("adb", "get-serialno")  # rejects missing/unauthorized/ambiguous devices
    info = run("adb", "shell", "dumpsys", "package", package)
    match = re.search(r"versionCode=(\d+)", info)
    if not match or int(match[1]) >= record["version_code"]:
        raise ValueError(
            "Atualização exige instalação existente com código estritamente inferior."
        )
    paths = run("adb", "shell", "pm", "path", package)
    base = next(
        (
            p.removeprefix("package:").strip()
            for p in paths.splitlines()
            if p.strip().endswith("/base.apk")
        ),
        None,
    )
    if not base or not re.fullmatch(r"/data/app/[A-Za-z0-9_./+=~-]+/base.apk", base):
        raise ValueError("Não foi possível verificar a instalação atual.")
    with tempfile.TemporaryDirectory(prefix="bath-installed-") as temp:
        old = Path(temp) / "installed.apk"
        run("adb", "pull", base, old)
        tools = Path(os.environ["ANDROID_HOME"]) / "build-tools/36.0.0"
        signing = run(tools / "apksigner", "verify", "--print-certs", old)
        if [x for x in signing.splitlines() if "certificate SHA-256 digest:" in x] != [
            f"Signer #1 certificate SHA-256 digest: {CERTIFICATE}"
        ]:
            raise ValueError(
                "Certificado instalado incompatível; atualização recusada."
            )
    run("adb", "install", "-r", Path(directory) / "bath-royale.apk")
    after = run("adb", "shell", "dumpsys", "package", package)
    if (
        not re.search(r"versionCode=" + str(record["version_code"]) + r"\b", after)
        or record["version_name"] not in after
    ):
        raise ValueError(
            "A atualização não foi confirmada; não limpar dados nem desinstalar."
        )
    return {
        "installed": True,
        "version_code": record["version_code"],
        "package": package,
    }


def gate(repo, enabled):
    gh(
        "variable",
        "set",
        "ALPHA_RELEASE_APPROVED",
        "-R",
        repo,
        "--body",
        "true" if enabled else "false",
    )
    actual = gh("variable", "get", "ALPHA_RELEASE_APPROVED", "-R", repo).strip()
    if actual != ("true" if enabled else "false"):
        raise ValueError(
            "Não foi possível confirmar o estado da autorização; reconciliar."
        )


def binding_for(request):
    state = source(strict=True)
    record = verify_record(request["directory"])
    if record["channel"] != "candidate" or record["source"] != state["source"]:
        raise ValueError("A publicação exige o candidate do commit revisto atual.")
    if (
        checksum(ROOT / "docs/releases/alpha-notes.md") != record["notes_hash"]
        or digest(public_config(request["public_config"])) != record["config_hash"]
    ):
        raise ValueError(
            "Notas ou configuração mudaram após a compilação; nova revisão obrigatória."
        )
    if api(request["repo"], "git/ref/heads/main")["object"]["sha"] != state["source"]:
        raise ValueError(
            "A publicação exige o commit atual de main no repositório oficial."
        )
    remote_config = configuration(
        gh("variable", "get", "SUPABASE_URL", "-R", request["repo"]).strip(),
        gh(
            "variable", "get", "SUPABASE_PUBLISHABLE_KEY", "-R", request["repo"]
        ).strip(),
    )
    if digest(remote_config) != record["config_hash"]:
        raise ValueError(
            "A configuração pública GitHub diverge da configuração revista."
        )
    latest = api(request["repo"], "releases/latest")
    published = int(re.fullmatch(r"alpha-(\d+)", latest["tag_name"])[1])
    # Semantic downgrades/reuse are forbidden, including a patch at the old version.
    prior = re.search(r"v(\d+\.\d+\.\d+)", latest["name"])
    if (
        not prior
        or tuple(map(int, record["version"].split(".")))
        <= tuple(map(int, prior[1].split(".")))
        or record["version_code"] <= published
    ):
        raise ValueError(
            "Publicação exige versão semântica e código Android superiores à última versão."
        )
    return {
        "allocation": record["allocation"],
        "artifact": record["sha256"],
        "notes": record["notes_hash"],
        "configuration": record["config_hash"],
        "certificate": CERTIFICATE,
        "checks": ci_required(request["repo"], state["source"]),
    }


def publish(request):
    binding = binding_for(request)
    approval = digest(binding)
    if not request.get("confirm"):
        return {
            "approved": False,
            "preview": binding,
            "confirmation": approval,
            "message": "Revê commit, APK, notas e CI; --confirm autoriza a publicação pública exata.",
        }
    if request["confirm"] != approval:
        raise ValueError(
            "Aprovação antiga ou divergente; revê uma nova pré-visualização."
        )
    repo = request["repo"]
    ledger = Ledger(repo)
    if gh("variable", "get", "ALPHA_RELEASE_APPROVED", "-R", repo).strip() != "false":
        raise ValueError("Autorização já ativa; reconciliar antes de publicar.")
    ledger.acquire(binding)
    # If killed/network lost after acquire, the ledger remains blocking. A timeout
    # expires approval but never frees exclusion; reconcile disables the gate first.
    completed = False
    try:
        ledger.assert_lease(binding)
        gate(repo, True)
        from publish_preview import publish as draft_publish

        allocation = binding["allocation"]
        env = {
            "GH_REPO": repo,
            "GITHUB_SHA": allocation["source"],
            "BUILD_NUMBER": str(allocation["code"]),
            "CONFIGURED_ALPHA": "true",
        }
        with contextlib.ExitStack() as stack:
            previous = {k: os.environ.get(k) for k in env}
            os.environ.update(env)
            stack.callback(
                lambda: [
                    os.environ.pop(k, None)
                    if v is None
                    else os.environ.__setitem__(k, v)
                    for k, v in previous.items()
                ]
            )

            def guard():
                ledger.assert_lease(binding)
                if binding_for(request) != binding:
                    raise ValueError(
                        "Origem, APK, configuração, notas ou CI mudaram; aprovação inválida."
                    )
                if (
                    gh("variable", "get", "ALPHA_RELEASE_APPROVED", "-R", repo).strip()
                    != "true"
                ):
                    raise ValueError("Autorização desativada; publicação recusada.")

            draft_publish(Path(request["directory"]), guard=guard)
        downloaded = download(
            {
                "repo": repo,
                "tag": "alpha-" + str(allocation["code"]),
                "directory": request["verification_directory"],
                "expected_source": allocation["source"],
            }
        )
        if downloaded["sha256"] != binding["artifact"]:
            raise ValueError(
                "O APK publicado diverge; publicação incompleta, preservar evidência."
            )
        completed = True
        return {
            "published": True,
            "tag": "alpha-" + str(allocation["code"]),
            "verified": downloaded,
            "message": "Atualiza as ligações README apenas após esta verificação.",
        }
    finally:
        # Do not clear the ledger unless disabling and readback both succeed.
        gate(repo, False)
        if completed:
            ledger.release(binding)


def reconcile(request):
    ledger = Ledger(request["repo"])
    _, state = ledger.read()
    binding = state["publication"]["binding"] if state["publication"] else None
    if not request.get("confirm"):
        return {
            "publication": state["publication"],
            "confirmation": digest(state),
            "message": "Confirma o estado exato para desativar o gate; não elimina versões nem retoma publicação.",
        }
    if request["confirm"] != digest(state):
        raise ValueError("O estado mudou; revê a reconciliação.")
    gate(request["repo"], False)
    # Releasing an unexpired operation could race its publisher. It must expire
    # first; all publishers recheck the lease immediately before public exposure.
    if state["publication"]:
        import datetime as dt

        if dt.datetime.fromisoformat(state["publication"]["expires"]) > dt.datetime.now(
            dt.UTC
        ):
            raise ValueError(
                "Gate desativado; operação ainda tem lease. Aguarda expiração e confirma de novo."
            )
        if not request.get("publisher_stopped"):
            raise ValueError(
                "Gate desativado; confirma que o processo anterior terminou antes de libertar a exclusão."
            )
        ledger.release(binding)
    return {"reconciled": True, "gate": False}


def download(request):
    tag = request["tag"]
    if not re.fullmatch(r"alpha-\d+", tag):
        raise ValueError("Seleciona uma versão alfa pública exata.")
    release = api(request["repo"], "releases/tags/" + tag)
    if release["draft"] or release["prerelease"] or release["tag_name"] != tag:
        raise ValueError("Versão incompleta ou metadados incompatíveis.")
    if (
        request.get("expected_source")
        and release["target_commitish"] != request["expected_source"]
    ):
        raise ValueError("Commit publicado divergente.")
    directory = safe_directory(request["directory"], create=True)
    assets = {x["name"]: x for x in release["assets"]}
    if set(assets) != {"bath-royale.apk", "SHA256SUMS"}:
        raise ValueError("Conjunto de assets incompleto ou inesperado.")
    for name, asset in assets.items():
        url = asset["browser_download_url"]
        prefix = f"https://github.com/{request['repo']}/releases/download/{tag}/"
        if url != prefix + name:
            raise ValueError("URL de descarga divergente.")
        path = directory / name
        # Deliberately anonymous HTTPS request; never attach gh authentication.
        with (
            urllib.request.urlopen(url, timeout=120) as response,
            path.open("xb") as stream,
        ):
            shutil.copyfileobj(response, stream)
        path.chmod(0o600)
        if path.stat().st_size != asset["size"] or asset.get("digest") not in (
            None,
            "sha256:" + checksum(path),
        ):
            raise ValueError("Digest/tamanho público divergente.")
    apk = directory / "bath-royale.apk"
    expected = checksum(apk) + "  ./bath-royale.apk\n"
    if (directory / "SHA256SUMS").read_text() != expected:
        raise ValueError("Checksum público divergente.")
    version = re.search(r"v(\d+\.\d+\.\d+)", release["name"])
    if not version:
        raise ValueError("Versão pública ausente.")
    number = tag.removeprefix("alpha-")
    with contextlib.redirect_stdout(io.StringIO()):
        verify_apk(str(apk), number, f"{version[1]}-alpha.{number}")
    ref = api(request["repo"], "git/ref/tags/" + tag)
    if (
        ref["object"]["type"] != "commit"
        or ref["object"]["sha"] != release["target_commitish"]
    ):
        raise ValueError("Tag/commit público divergente.")
    return {
        "tag": tag,
        "source": release["target_commitish"],
        "sha256": checksum(apk),
        "certificate": CERTIFICATE,
        "anonymous_download": True,
        "url": release["html_url"],
    }


def verify_public(directory, repo):
    directory = safe_directory(directory)
    match = re.match(r"(alpha-\d+)(?:-|$)", directory.name)
    if not match:
        raise ValueError("Falta a tag pública no nome da pasta canónica.")
    tag = match[1]
    release = api(repo, "releases/tags/" + tag)
    version = re.search(r"v(\d+\.\d+\.\d+)", release["name"])
    if release["draft"] or release["prerelease"] or not version:
        raise ValueError("Versão pública incompleta.")
    apk = private_file(directory / "bath-royale.apk")
    assets = {x["name"]: x for x in release["assets"]}
    if (
        set(assets) != {"bath-royale.apk", "SHA256SUMS"}
        or apk.stat().st_size != assets["bath-royale.apk"]["size"]
    ):
        raise ValueError("Os ficheiros públicos divergem.")
    if (directory / "SHA256SUMS").read_text() != checksum(
        apk
    ) + "  ./bath-royale.apk\n" or assets["bath-royale.apk"].get(
        "digest"
    ) != "sha256:" + checksum(apk):
        raise ValueError("O checksum público diverge.")
    with contextlib.redirect_stdout(io.StringIO()):
        verify_apk(
            str(apk),
            tag.removeprefix("alpha-"),
            version[1] + "-alpha." + tag.removeprefix("alpha-"),
        )
    verify_distribution_payload(apk)
    ref = api(repo, "git/ref/tags/" + tag)
    if (
        ref["object"]["type"] != "commit"
        or ref["object"]["sha"] != release["target_commitish"]
    ):
        raise ValueError("A tag e o commit públicos divergem.")
    return {
        "tag": tag,
        "sha256": checksum(apk),
        "source": release["target_commitish"],
        "certificate": CERTIFICATE,
        "verified": True,
        "channel": "alpha",
        "package": "com.example.bath_royale",
        "version_code": int(tag.removeprefix("alpha-")),
        "version_name": version[1] + "-alpha." + tag.removeprefix("alpha-"),
    }


def execute(request):
    if request.get("protocol") != PROTOCOL:
        raise ValueError("Protocolo de versões incompatível.")
    action = request["action"]
    if action == "version":
        return {"version": current()}
    if action == "source":
        return source(strict=request.get("strict", False))
    if action == "bump":
        if request.get("apply"):
            source(strict=True)
        return bump(request["part"], apply=request.get("apply", False))
    if action == "build":
        return build(request)
    if action == "verify":
        return (
            verify_record(request["directory"])
            if (Path(request["directory"]) / "release.json").exists()
            else verify_public(request["directory"], request["repo"])
        )
    if action == "install":
        return install(request["directory"], request.get("repo"))
    if action == "publish":
        return publish(request)
    if action == "reconcile":
        return reconcile(request)
    if action == "download":
        return download(request)
    raise ValueError("Operação de versões desconhecida.")


if __name__ == "__main__":

    def terminate(*_):
        raise SystemExit(143)

    signal.signal(signal.SIGTERM, terminate)
    try:
        # Bound request size; sensitive subprocess output never reaches protocol stdout.
        value = json.loads(sys.stdin.read(100000))
        result = execute(value)
        print(json.dumps(result))
    except Exception as failure:  # noqa: BLE001 - private protocol error boundary
        message = (
            str(failure)
            if isinstance(failure, ValueError)
            else "Operação recusada; verifica pré-requisitos e reconcilia o gate se necessário. Diagnósticos privados omitidos."
        )
        print(json.dumps({"error": message}))
        sys.exit(2)
