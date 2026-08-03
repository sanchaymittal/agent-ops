#!/usr/bin/env python3
"""Versioned install/check/upgrade support for the agent-ops template."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys

MANIFEST = ".orchestration/install-manifest.json"
EXCLUDE = {".DS_Store", "__pycache__"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def config_digest(configuration: dict[str, str]) -> str:
    encoded = json.dumps(configuration, sort_keys=True, separators=(",", ":")).encode()
    return digest(encoded)


def files(root: pathlib.Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in EXCLUDE for part in path.parts):
            continue
        rel = path.relative_to(root).as_posix()
        if rel in {MANIFEST, ".orchestration/.lease/meta", "CLAUDE.md"}:
            continue
        yield rel, path


def rendered(source: pathlib.Path, config: dict[str, str]) -> bytes:
    data = source.read_bytes()
    text = data.decode("utf-8")
    replacements = {
        "PROJECT_NAME": config["project_name"],
        "VERIFY_CMD": config["verify_command"],
    }
    for key, value in replacements.items():
        text = text.replace("{{" + key + "}}", value)
    return text.encode("utf-8")


def config_from_manifest(manifest: dict) -> dict[str, str]:
    return manifest["configuration"]


def stamp(args: argparse.Namespace) -> int:
    source, stage = pathlib.Path(args.source), pathlib.Path(args.stage)
    configuration = {
        "project_name": args.project_name,
        "verify_command": args.verify_command,
    }
    installed = {rel: digest(path.read_bytes()) for rel, path in files(stage)}
    manifest = {
        "template_version": (source / ".orchestration/VERSION").read_text().strip(),
        "schema_version": 2,
        "configuration": configuration,
        "rendered_configuration": config_digest(configuration),
        "source_files": installed,
        "installed_files": installed,
    }
    (stage / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return 0


def inspect(source: pathlib.Path, target: pathlib.Path, manifest: dict):
    config = config_from_manifest(manifest)
    installed = manifest.get("installed_files", {})
    expected_source = {}
    for rel, path in files(source):
        expected_source[rel] = digest(rendered(path, config))
    modified, outdated, missing = [], [], []
    for rel, expected in installed.items():
        path = target / rel
        if not path.exists() and not path.is_symlink():
            missing.append(rel)
        elif digest(path.read_bytes()) != expected:
            modified.append(rel)
    for rel, expected in expected_source.items():
        if rel not in modified and manifest.get("source_files", {}).get(rel) != expected:
            outdated.append(rel)
    obsolete = sorted(set(installed) - set(expected_source))
    return modified, outdated, missing, expected_source, obsolete


def check(args: argparse.Namespace) -> int:
    target = pathlib.Path(args.target).resolve()
    path = target / MANIFEST
    if not path.is_file():
        print(f"blocked: install: manifest missing: {path}", file=sys.stderr)
        return 1
    manifest = json.loads(path.read_text())
    source = pathlib.Path(args.source).resolve()
    modified, outdated, missing, _, obsolete = inspect(source, target, manifest)
    configuration = manifest.get("configuration", {})
    config_ok = bool(configuration) and manifest.get("rendered_configuration") == config_digest(configuration)
    print(json.dumps({"template_version": manifest.get("template_version"),
                      "modified_managed": modified, "untouched_outdated": outdated,
                      "missing_managed": missing, "obsolete_managed": obsolete,
                      "configuration_stamp_ok": config_ok}, sort_keys=True))
    return 1 if modified or outdated or missing or obsolete or not config_ok else 0


def upgrade(args: argparse.Namespace) -> int:
    source, target = pathlib.Path(args.source).resolve(), pathlib.Path(args.target).resolve()
    path = target / MANIFEST
    if not path.is_file():
        print(f"blocked: install: manifest missing: {path}", file=sys.stderr)
        return 1
    manifest = json.loads(path.read_text())
    modified, _, missing, expected_source, obsolete = inspect(source, target, manifest)
    installed = dict(manifest.get("installed_files", {}))
    modified_set = set(modified)
    updated = []
    for rel, source_path in files(source):
        destination = target / rel
        if rel in modified_set:
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(rendered(source_path, manifest["configuration"]))
        shutil.copymode(source_path, destination, follow_symlinks=False)
        installed[rel] = digest(destination.read_bytes())
        updated.append(rel)
    # A stale managed file is not deleted automatically. It remains visible as
    # a missing/obsolete item for a human-controlled merge.
    manifest["template_version"] = (source / ".orchestration/VERSION").read_text().strip()
    manifest["source_files"] = expected_source
    manifest["installed_files"] = installed
    manifest["rendered_configuration"] = config_digest(manifest["configuration"])
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"updated": updated, "preserved_modified": modified,
                      "missing_managed": missing, "obsolete_managed": obsolete}, sort_keys=True))
    return 0


def parser():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    stamp_ap = sub.add_parser("stamp")
    stamp_ap.add_argument("--source", required=True)
    stamp_ap.add_argument("--stage", required=True)
    for name in ("project_name", "verify_command"):
        stamp_ap.add_argument("--" + name.replace("_", "-"), required=True)
    stamp_ap.set_defaults(fn=stamp)
    for name in ("check", "upgrade"):
        p = sub.add_parser(name)
        p.add_argument("--source", required=True)
        p.add_argument("--target", required=True)
        p.set_defaults(fn=check if name == "check" else upgrade)
    return ap


if __name__ == "__main__":
    arguments = parser().parse_args()
    raise SystemExit(arguments.fn(arguments))
