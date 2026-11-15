#!/usr/bin/env python3
"""
The ESP-IDF versions file (idf_versions.yml): read it, check it, and turn it into CI matrices.

Used by manage_idf.sh, generate_matrix.py and the tab completion, and on its own:

    python3 idf_versions.py list                          # table of every version
    python3 idf_versions.py list --format names           # one version per line
    python3 idf_versions.py get release/v6.1 ref          # one field
    python3 idf_versions.py matrix --scope pr             # GitHub Actions matrix of the versions CI builds
    python3 idf_versions.py scope                         # pr or full, from GITHUB_EVENT_NAME and GITHUB_REF
    python3 idf_versions.py check                         # validate the file

Works with the Python 3.9 of macOS and without PyYAML: the file keeps a one-line-per-entry form that the fallback
reader here parses (see the format rules at the top of idf_versions.yml); with PyYAML installed both readers run
in `check` and must agree.

SPDX-License-Identifier: MIT
Copyright (c) 2026 The Kokeb Labs Authors
"""

import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

VERSIONS_FILE = Path(__file__).resolve().parent / "idf_versions.yml"

STATUSES = ("service", "maintenance", "eol", "preview")
CI_VALUES = ("pr", "full", "none")
KEYS = ("version", "ref", "status", "ci", "targets", "preview", "released")
REQUIRED_KEYS = ("version", "status", "ci", "targets", "released")

# Espressif support periods (SUPPORT_POLICY.md): 12 months of service, then 18 of maintenance.
SERVICE_MONTHS = 12
SUPPORT_MONTHS = 30


class VersionsError(Exception):
    """The versions file is missing or malformed."""


# ---------------------------------------------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------------------------------------------

def _scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    return text


def _split_top(text):
    """Split on commas outside [] (the values of this file never contain quoted commas)."""
    parts, depth, cur = [], 0, ""
    for ch in text:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


def _list(text):
    text = text.strip()
    if not (text.startswith("[") and text.endswith("]")):
        raise ValueError("expected [a, b, ...]")
    inner = text[1:-1].strip()
    return [_scalar(x) for x in inner.split(",")] if inner else []


def parse_lines(text):
    """The fallback reader: the restricted one-line-per-entry form of idf_versions.yml, no PyYAML needed."""
    data = {"target_sets": {}, "versions": []}
    section = None
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.split(" #", 1)[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip() or line.strip() == "---":
            continue
        if not line.startswith(" "):
            m = re.match(r"^([A-Za-z_]+):\s*$", line)
            if not m:
                raise VersionsError(f"line {number}: expected a top-level key, got: {raw.strip()}")
            section = m.group(1)
            if section not in data:
                raise VersionsError(f"line {number}: unknown section '{section}'")
            continue
        body = line.strip()
        try:
            if section == "target_sets":
                m = re.match(r"^([A-Za-z0-9_.-]+):\s*(\[.*\])$", body)
                if not m:
                    raise ValueError("expected `name: [target, ...]` on one line")
                data["target_sets"][m.group(1)] = _list(m.group(2))
            elif section == "versions":
                m = re.match(r"^-\s*\{(.*)\}$", body)
                if not m:
                    raise ValueError("expected `- {key: value, ...}` on one line")
                entry = {}
                for part in _split_top(m.group(1)):
                    if ":" not in part:
                        raise ValueError(f"expected key: value, got '{part.strip()}'")
                    key, value = part.split(":", 1)
                    value = value.strip()
                    entry[key.strip()] = _list(value) if value.startswith("[") else _scalar(value)
                data["versions"].append(entry)
            else:
                raise ValueError("entry outside a section")
        except ValueError as exc:
            raise VersionsError(f"line {number}: {exc}: {raw.strip()}") from None
    return data


def parse_yaml(text):
    """The same file through PyYAML (None when PyYAML is not installed or IDF_VERSIONS_NO_YAML is set)."""
    if os.environ.get("IDF_VERSIONS_NO_YAML"):
        return None
    try:
        import yaml  # noqa: PLC0415 - optional
    except ImportError:
        return None
    data = yaml.safe_load(text) or {}
    for entry in data.get("versions") or []:
        for key, value in list(entry.items()):
            if isinstance(value, (datetime.date, datetime.datetime)):
                entry[key] = value.isoformat()
            elif value is not None and not isinstance(value, list):
                entry[key] = str(value)
    return {"target_sets": data.get("target_sets") or {}, "versions": data.get("versions") or []}


def load(path=None):
    """The versions, each a dict with every key resolved: ref defaulted, target sets expanded to lists."""
    path = Path(path or os.environ.get("IDF_VERSIONS_FILE") or VERSIONS_FILE)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise VersionsError(f"cannot read {path}: {exc}") from None
    data = parse_yaml(text) or parse_lines(text)
    return resolve(data)


def resolve(data):
    sets = data.get("target_sets") or {}
    out = []
    for entry in data.get("versions") or []:
        e = dict(entry)
        e.setdefault("ref", e.get("version"))
        for key in ("targets", "preview"):
            value = e.get(key)
            if value is None:
                e[key] = []
            elif isinstance(value, list):
                e[key] = list(value)
            else:
                e[key] = list(sets.get(value, [])) if value in sets else None
                e[key + "_set"] = value
        out.append(e)
    return out


def find(versions, name):
    """The entry for a version name, else None. A tag such as v6.0.3 also matches its release branch entry."""
    for e in versions:
        if e["version"] == name or e["ref"] == name:
            return e
    mm = major_minor(name)
    if mm and re.match(r"^v\d+\.\d+(\.\d+)?$", name):
        for e in versions:
            if major_minor(e["version"]) == mm:
                return e
    return None


def ref_for(versions, name):
    """The git ref to clone for a name: the ref of its own entry; a tag such as v6.0.3 is cloned as itself."""
    for e in versions:
        if e["version"] == name or e["ref"] == name:
            return e["ref"]
    return name


def major_minor(name):
    """"6.1" for release/v6.1, v6.1, v6.1.2 or v6.1-rc1; None for master and other refs."""
    m = re.search(r"v(\d+)\.(\d+)", name or "")
    return f"{m.group(1)}.{m.group(2)}" if m else None


def default_version(versions):
    """The version built on every CI run (ci: pr), else the first listed."""
    for e in versions:
        if e.get("ci") == "pr":
            return e["version"]
    return versions[0]["version"] if versions else None


def safe_names(version):
    """The derived names generate_matrix.py and the build folders use."""
    return {
        "idf_version_docker": version.replace("/", "-"),
        "idf_version_file": version.replace("/", "_").replace(".", "_"),
    }


# ---------------------------------------------------------------------------------------------------------------
# Scope (which versions a CI run builds)
# ---------------------------------------------------------------------------------------------------------------

# The events of a full run; ci-tools ru-build (idf_scope: auto) uses the same table.
FULL_EVENTS = ("schedule", "workflow_dispatch", "release", "repository_dispatch")


def scope_for_event(event_name, ref=""):
    """full for a tag push and the FULL_EVENTS; pr, the cheap scope, for every other event (pull requests,
    branch pushes, merge_group, workflow_run, an event this table does not know)."""
    if event_name == "push" and (ref or "").startswith("refs/tags/"):
        return "full"
    if event_name in FULL_EVENTS:
        return "full"
    return "pr"


def in_scope(entry, scope):
    """Whether CI builds this version in this scope (all: every listed version, whatever its ci value)."""
    if scope == "all":
        return True
    ci = entry.get("ci", "none")
    if scope == "pr":
        return ci == "pr"
    if scope == "full":
        return ci in ("pr", "full")
    raise ValueError(f"unknown scope '{scope}'")


# ---------------------------------------------------------------------------------------------------------------
# Checking
# ---------------------------------------------------------------------------------------------------------------

def _add_months(date, months):
    y, m = divmod(date.month - 1 + months, 12)
    return datetime.date(date.year + y, m + 1, min(date.day, 28))


def expected_status(released, today):
    """The support period a release date puts a version in today, by Espressif's 12 + 18 month rule."""
    if today < _add_months(released, SERVICE_MONTHS):
        return "service"
    if today < _add_months(released, SUPPORT_MONTHS):
        return "maintenance"
    return "eol"


def check(path=None, today=None):
    """Errors (the file is wrong) and warnings (the file is out of date)."""
    path = Path(path or os.environ.get("IDF_VERSIONS_FILE") or VERSIONS_FILE)
    errors, warnings = [], []
    try:
        text = path.read_text(encoding="utf-8")
        lines_data = parse_lines(text)
    except (OSError, VersionsError) as exc:
        return [str(exc)], []
    yaml_data = parse_yaml(text)
    if yaml_data is not None and resolve(yaml_data) != resolve(lines_data):
        errors.append("PyYAML and the one-line reader disagree: keep one entry per line (see the file header)")
    sets = lines_data["target_sets"]
    seen = set()
    pr_count = 0
    today = today or datetime.date.today()
    for e in lines_data["versions"]:
        name = e.get("version", "?")
        for key in REQUIRED_KEYS:
            if key not in e:
                errors.append(f"{name}: missing '{key}'")
        for key in e:
            if key not in KEYS:
                errors.append(f"{name}: unknown key '{key}'")
        if name in seen:
            errors.append(f"{name}: listed twice")
        seen.add(name)
        if e.get("status") not in STATUSES:
            errors.append(f"{name}: status must be one of {', '.join(STATUSES)}")
        if e.get("ci") not in CI_VALUES:
            errors.append(f"{name}: ci must be one of {', '.join(CI_VALUES)}")
        pr_count += e.get("ci") == "pr"
        for key in ("targets", "preview"):
            value = e.get(key)
            if value is not None and not isinstance(value, list) and value not in sets:
                errors.append(f"{name}: {key} names the unknown target set '{value}'")
        if e.get("status") == "eol" and e.get("ci") in ("pr", "full"):
            errors.append(f"{name}: an end-of-life version cannot be built by CI (set ci: none)")
        released = e.get("released")
        if released:
            try:
                date = datetime.date.fromisoformat(released)
            except ValueError:
                errors.append(f"{name}: released must be YYYY-MM-DD")
                continue
            want = expected_status(date, today)
            if e.get("status") in ("service", "maintenance", "eol") and e.get("status") != want:
                warnings.append(f"{name}: status is {e.get('status')}, the support policy says {want} today")
    if pr_count != 1:
        errors.append(f"exactly one version must have ci: pr (found {pr_count})")
    return errors, warnings


# ---------------------------------------------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------------------------------------------

def _matrix(versions, scope, target=None):
    include = []
    for e in versions:
        if not in_scope(e, scope):
            continue
        if target and target not in (e["targets"] or []) + (e["preview"] or []):
            continue
        row = {"idf_version": e["version"], "idf_ref": e["ref"], "idf_status": e["status"]}
        row.update(safe_names(e["version"]))
        if target:
            row["target"] = target
        include.append(row)
    return {"include": include}


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="idf_versions.py",
        description="Read, check and turn into CI matrices the ESP-IDF versions file (idf_versions.yml)")
    parser.add_argument("--file", help="versions file (default: idf_versions.yml next to this script, or "
                                       "$IDF_VERSIONS_FILE)")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("list", help="the versions")
    p.add_argument("--format", choices=["table", "names", "json", "tsv"], default="table")
    p.add_argument("--scope", choices=["pr", "full", "all"], default="all",
                   help="only the versions CI builds in this scope")

    p = sub.add_parser("get", help="one field of one version")
    p.add_argument("version")
    p.add_argument("field", choices=list(KEYS) + ["eol"])

    p = sub.add_parser("matrix", help="GitHub Actions matrix (JSON) of the versions a scope builds")
    p.add_argument("--scope", choices=["pr", "full", "auto"], default="auto",
                   help="auto: from GITHUB_EVENT_NAME and GITHUB_REF (see scope); ci: none is never in a matrix")
    p.add_argument("--target", help="only versions supporting this chip, with a target field")

    p = sub.add_parser("scope", help="pr or full for a CI event (default: GITHUB_EVENT_NAME, GITHUB_REF)")
    p.add_argument("--event", default=os.environ.get("GITHUB_EVENT_NAME", ""))
    p.add_argument("--ref", default=os.environ.get("GITHUB_REF", ""))

    sub.add_parser("default", help="the version CI builds on every run (ci: pr)")
    sub.add_parser("check", help="validate the file; warnings when a status is behind the support policy")

    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help(sys.stderr)
        return 2
    try:
        if args.command == "check":
            errors, warnings = check(args.file)
            for w in warnings:
                print(f"warning: {w}", file=sys.stderr)
            for e in errors:
                print(f"error: {e}", file=sys.stderr)
            if not errors:
                print(f"{args.file or 'idf_versions.yml'}: ok")
            return 1 if errors else 0
        versions = load(args.file)
        if args.command == "list":
            rows = [e for e in versions if in_scope(e, args.scope)]
            if args.format == "names":
                for e in rows:
                    print(e["version"])
            elif args.format == "json":
                print(json.dumps(rows))
            elif args.format == "tsv":
                for e in rows:
                    print("\t".join([e["version"], e["ref"], e["status"], e["ci"], ",".join(e["targets"] or []),
                                     ",".join(e["preview"] or []), e.get("released", "")]))
            else:
                print(f"{'VERSION':<16} {'REF':<16} {'STATUS':<12} {'CI':<5} {'RELEASED':<11} TARGETS")
                for e in rows:
                    targets = " ".join(e["targets"] or [])
                    if e["preview"]:
                        targets += "  (preview: " + " ".join(e["preview"]) + ")"
                    print(f"{e['version']:<16} {e['ref']:<16} {e['status']:<12} {e['ci']:<5} "
                          f"{e.get('released', ''):<11} {targets}")
        elif args.command == "get":
            e = find(versions, args.version)
            if e is None:
                print(f"error: {args.version} is not in the versions file", file=sys.stderr)
                return 1
            if args.field == "ref":
                print(ref_for(versions, args.version))
            elif args.field == "eol":
                date = datetime.date.fromisoformat(e["released"])
                print(_add_months(date, SUPPORT_MONTHS).strftime("%Y-%m"))
            else:
                value = e.get(args.field)
                print(" ".join(value) if isinstance(value, list) else (value or ""))
        elif args.command == "matrix":
            scope = args.scope
            if scope == "auto":
                scope = scope_for_event(os.environ.get("GITHUB_EVENT_NAME", ""), os.environ.get("GITHUB_REF", ""))
            print(json.dumps(_matrix(versions, scope, args.target)))
        elif args.command == "scope":
            print(scope_for_event(args.event, args.ref))
        elif args.command == "default":
            print(default_version(versions) or "")
    except VersionsError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
