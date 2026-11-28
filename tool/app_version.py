"""Application version protocol. pubspec.yaml is the only semantic authority."""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHANNELS = ("development", "candidate", "alpha")


def current(root=ROOT):
    return parse((Path(root) / "pubspec.yaml").read_text())


def parse(text):
    matches = re.findall(r"^version:\s*(\d+\.\d+\.\d+)\s*$", text, re.MULTILINE)
    if len(matches) != 1 or any(str(int(x)) != x for x in matches[0].split(".")):
        raise ValueError(
            "pubspec.yaml exige uma única versão canónica major.minor.patch."
        )
    return matches[0]


def metadata(channel, number, root=ROOT, *, pubspec_text=None):
    if (
        channel not in CHANNELS
        or type(number) is not int
        or not 1 <= number <= 2100000000
    ):
        raise ValueError("Canal ou código de compilação inválido.")
    if channel == "development" and number != 1:
        raise ValueError(
            "As compilações de desenvolvimento exigem código 1 e um pacote separado."
        )
    version = current(root) if pubspec_text is None else parse(pubspec_text)
    name = f"{version}-{'dev' if channel == 'development' else 'alpha'}.{number}"
    return {
        "protocol": 1,
        "version": version,
        "channel": channel,
        "version_name": name,
        "version_code": number,
        "package": "com.example.bath_royale"
        + (".development" if channel == "development" else ""),
        "runtime_version": name,
    }


def bump(part, *, apply=False, root=ROOT):
    before = current(root)
    if part not in ("major", "minor", "patch"):
        raise ValueError("Seleciona major, minor ou patch.")
    values = list(map(int, before.split(".")))
    index = ("major", "minor", "patch").index(part)
    values[index] += 1
    values[index + 1 :] = [0] * (2 - index)
    after = ".".join(map(str, values))
    if apply:
        path = Path(root) / "pubspec.yaml"
        path.write_text(
            re.sub(
                r"^version:.*$",
                "version: " + after,
                path.read_text(),
                count=1,
                flags=re.MULTILINE,
            )
        )
    return {"before": before, "after": after, "applied": apply}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--channel", choices=CHANNELS, default="development")
    p.add_argument("--number", type=int, default=1)
    a = p.parse_args()
    print(json.dumps(metadata(a.channel, a.number)))
