"""Append-only shared GitHub build allocator and expiring publication exclusion.

Each write creates a child of the observed ledger commit. Updating its branch
without force rejects a concurrent sibling. Orphan objects never allocate codes.
Network failures are unknown outcomes: retry with the SAME request identifier.
"""

import base64
import copy
import datetime as dt
import hashlib
import json
import os
import re
import subprocess

BRANCH = "managed-build-ledger"
GENESIS = "managed-build-ledger-origin"
# All historical tags <=1046; last old validation run 58 =>1058. Reserve the
# entire legacy interval as a migration fence; no old counter participates again.
FLOOR = 1000000
MAX_CODE = 2100000000


class RemoteError(RuntimeError):
    def __init__(self, status=None):
        super().__init__(
            "GitHub indisponível ou operação recusada; reconciliar antes de repetir."
        )
        self.status = status


def gh(*args, payload=None):
    env = {
        k: os.environ[k]
        for k in ("PATH", "HOME", "LANG", "GH_TOKEN")
        if k in os.environ
    }
    env["GH_PROMPT_DISABLED"] = "1"
    r = subprocess.run(
        ["gh", *args],
        input=None if payload is None else json.dumps(payload),
        text=True,
        check=False,
        capture_output=True,
        env=env,
        timeout=60,
    )
    if r.returncode:
        match = re.search(r"HTTP (\d{3})", r.stderr)
        raise RemoteError(int(match[1]) if match else None)
    return r.stdout


class Ledger:
    def __init__(self, repo):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
            raise ValueError("Repositório inválido.")
        self.repo = repo

    def api(self, path, payload=None, method=None):
        args = ["api", f"repos/{self.repo}/{path}"]
        if payload is not None:
            args += ["--method", method or "POST", "--input", "-"]
        return json.loads(gh(*args, payload=payload))

    def read(self):
        try:
            ref = self.api(f"git/ref/heads/{BRANCH}")["object"]["sha"]
        except RemoteError as e:
            if e.status == 404:
                try:
                    self.api(f"git/ref/tags/{GENESIS}")
                except RemoteError as anchor_error:
                    if anchor_error.status == 404:
                        return None, {
                            "format": 1,
                            "allocations": [],
                            "publication": None,
                        }
                    raise
                raise ValueError(
                    "O ramo de compilações está ausente mas a origem foi conservada; reconcilia sem reiniciar o contador."
                ) from None
            raise
        commit = self.api(f"git/commits/{ref}")
        tree = self.api(f"git/trees/{commit['tree']['sha']}")["tree"]
        entry = next(x for x in tree if x["path"] == "ledger.json")
        blob = self.api(f"git/blobs/{entry['sha']}")
        state = json.loads(base64.b64decode(blob["content"]))
        if state.get("format") != 1:
            raise ValueError("Formato do registo de compilações incompatível.")
        return ref, state

    def write(self, parent, value):
        tree = self.api(
            "git/trees",
            {
                "tree": [
                    {
                        "path": "ledger.json",
                        "mode": "100644",
                        "type": "blob",
                        "content": json.dumps(value, sort_keys=True),
                    }
                ]
            },
        )
        commit = self.api(
            "git/commits",
            {
                "message": "chore(release): append allocation observation",
                "tree": tree["sha"],
                "parents": [parent] if parent else [],
            },
        )
        if parent:
            self.api(
                f"git/refs/heads/{BRANCH}",
                {"sha": commit["sha"], "force": False},
                "PATCH",
            )
        else:
            self.api("git/refs", {"ref": f"refs/tags/{GENESIS}", "sha": commit["sha"]})
            self.api("git/refs", {"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})

    def change(self, mutate):
        for _ in range(8):
            parent, state = self.read()
            value = copy.deepcopy(state)
            result = mutate(value)
            if value == state:
                return result
            try:
                self.write(parent, value)
                return result
            except RemoteError as e:
                if e.status not in (409, 422):
                    raise
        raise ValueError(
            "Atualizações concorrentes; repete o mesmo identificador de pedido."
        )

    def tag_floor(self):
        refs = self.api("git/matching-refs/tags/")
        return max(
            [FLOOR]
            + [
                int(m[1])
                for row in refs
                if (m := re.fullmatch(r"refs/tags/(?:alpha|preview)-(\d+)", row["ref"]))
            ]
        )

    def allocate(self, request, source, version, *, minimum=0):
        if not re.fullmatch(r"[a-f0-9]{32}", request) or not re.fullmatch(
            r"[a-f0-9]{40}", source
        ):
            raise ValueError("É necessário o pedido e o commit exatos.")
        if (
            not re.fullmatch(r"\d+\.\d+\.\d+", version)
            or type(minimum) is not int
            or minimum < 0
        ):
            raise ValueError("Reserva de compilação inválida.")
        floor = max(self.tag_floor(), minimum)

        def mutate(state):
            for row in state["allocations"]:
                if row["request"] == request:
                    if row["source"] != source or row["version"] != version:
                        raise ValueError(
                            "O pedido já está associado a outra origem ou versão."
                        )
                    if row["code"] <= minimum:
                        raise ValueError(
                            "O código reservado já não supera a instalação observada; usa um novo pedido."
                        )
                    return row
            if state["publication"] is not None:
                raise ValueError(
                    "Publicação pendente; reconcilia antes de reservar outro código."
                )
            code = max([floor] + [r["code"] for r in state["allocations"]]) + 1
            if code > MAX_CODE:
                raise ValueError("Limite de códigos Android atingido.")
            row = {
                "request": request,
                "source": source,
                "version": version,
                "code": code,
            }
            state["allocations"].append(row)
            return row

        return self.change(mutate)

    def acquire(self, binding, now=None):
        now = now or dt.datetime.now(dt.UTC)

        def mutate(state):
            if state["publication"] is not None:
                raise ValueError(
                    "Já existe uma publicação ou aprovação ativa; reconcilia explicitamente."
                )
            rows = state["allocations"]
            if not rows or binding["allocation"] != rows[-1]:
                raise ValueError("Reserva antiga; existe um candidato mais recente.")
            lease = {
                "binding": binding,
                "expires": (now + dt.timedelta(minutes=90)).isoformat(),
            }
            state["publication"] = lease
            return lease

        return self.change(mutate)

    def assert_lease(self, binding):
        _, state = self.read()
        lease = state["publication"]
        if (
            not lease
            or lease["binding"] != binding
            or dt.datetime.fromisoformat(lease["expires"]) <= dt.datetime.now(dt.UTC)
        ):
            raise ValueError("Aprovação de publicação antiga ou expirada.")

    def release(self, binding):
        def mutate(state):
            if state["publication"] and state["publication"]["binding"] != binding:
                raise ValueError("A publicação pertence a outra operação.")
            state["publication"] = None

        self.change(mutate)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
