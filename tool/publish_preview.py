"""Resume draft publications; never modify an already published release."""

import hashlib
import json
import os
from pathlib import Path
import subprocess


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()


def api(path, *args):
    return json.loads(gh("api", path, *args))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_assets(release, directory, repo):
    assets = {asset["name"]: asset for asset in release["assets"]}
    require(set(assets) <= {"bath-royale.apk", "SHA256SUMS"}, "Unexpected assets")
    for name, asset in assets.items():
        remote = subprocess.check_output(
            [
                "gh",
                "api",
                f"repos/{repo}/releases/assets/{asset['id']}",
                "-H",
                "Accept: application/octet-stream",
            ]
        )
        require(remote == (directory / name).read_bytes(), f"Asset mismatch: {name}")
    return set(assets)


def release_presentation(number, alpha):
    # Public version comes from the source version, never the Android build code.
    from app_version import current

    root = Path(__file__).resolve().parents[1]
    version = current(root)
    title = f"Bath Royale v{version} — {'Alfa' if alpha else 'Desenvolvimento'}"
    notes = (
        (root / "docs/releases/alpha-notes.md").read_text().strip()
        if alpha
        else (
            "Pré-lançamento Android de desenvolvimento, sem configuração do serviço de contas. "
            "Para experimentar a alfa atual, consulta o README do projeto."
        )
    )
    return title, notes + (
        f"\n\n## Detalhes técnicos\n\nVersão apresentada: **v{version}**. "
        f"Compilação interna Android: **{number}**. "
        "O número de compilação identifica o APK e a ordem de atualização; "
        "não é a versão pública da aplicação."
    )


def publish(directory, *, guard=None):
    require(
        os.environ.get("CONFIGURED_ALPHA") == "true",
        "Development builds must not publish releases or assets",
    )
    require(callable(guard), "Exact publication lease required; use managed_release.py")
    guard()
    repo = os.environ["GH_REPO"]
    sha = os.environ["GITHUB_SHA"]
    number = os.environ["BUILD_NUMBER"]
    require(number.isdecimal(), "Invalid build number")
    alpha = os.environ.get("CONFIGURED_ALPHA") == "true"
    tag = f"{'alpha' if alpha else 'preview'}-{number}"
    apk = directory / "bath-royale.apk"
    expected = hashlib.sha256(apk.read_bytes()).hexdigest() + "  ./bath-royale.apk\n"
    require((directory / "SHA256SUMS").read_text() == expected, "Checksum mismatch")
    # List first: authentication/network errors must never be mistaken for absence.
    refs = api(f"repos/{repo}/git/matching-refs/tags/{tag}")
    refs = [ref for ref in refs if ref["ref"] == f"refs/tags/{tag}"]
    if refs:
        require(
            refs[0]["object"]["type"] == "commit" and refs[0]["object"]["sha"] == sha,
            "Tag belongs to another commit",
        )
    else:
        api(f"repos/{repo}/git/refs", "-f", f"ref=refs/tags/{tag}", "-f", f"sha={sha}")
    releases = api(f"repos/{repo}/releases?per_page=100", "--paginate", "--slurp")
    matches = [r for page in releases for r in page if r["tag_name"] == tag]
    if not matches:
        title, notes = release_presentation(number, alpha)
        notes += f"\n\nCommit de origem: `{sha}`"
        release = api(
            f"repos/{repo}/releases",
            "-f",
            f"tag_name={tag}",
            "-f",
            f"target_commitish={sha}",
            "-F",
            "draft=true",
            "-F",
            "prerelease=false",
            "-f",
            "make_latest=true",
            "-f",
            f"name={title}",
            "-f",
            f"body={notes}",
        )
    else:
        release = matches[0]
    release_path = f"repos/{repo}/releases/{release['id']}"
    release = api(release_path)
    require(
        not release["prerelease"] and release["target_commitish"] == sha,
        "Release identity mismatch",
    )
    existing = verify_assets(release, directory, repo)
    names = {"bath-royale.apk", "SHA256SUMS"}
    if not release["draft"]:
        require(
            existing == names, "Published release incomplete; refusing modification"
        )
        return
    for name in sorted(names - existing):
        gh("release", "upload", tag, str(directory / name))
    release = api(release_path)
    require(verify_assets(release, directory, repo) == names, "Incomplete draft")
    guard()
    gh("release", "edit", tag, "--draft=false", "--prerelease=false", "--latest")


if __name__ == "__main__":
    publish(Path("preview"))
