# ESP-IDF versions

`idf_versions.yml` lists the ESP-IDF versions these scripts know: the git ref each one is cloned from, the chips
it supports, where it is in Espressif's support periods, and whether CI builds it. `manage_idf.sh`,
`generate_matrix.py`, `idf_versions.py` and the tab completion all read it.

```bash
./scripts/manage_idf.sh available                  # the versions, marked when installed
python3 scripts/idf_versions.py list               # the same table
python3 scripts/idf_versions.py check              # validate the file
```

## The file

```yaml
target_sets:
  v5.5: [esp32, esp32s2, esp32s3, esp32c2, esp32c3, esp32c5, esp32c6, esp32c61, esp32h2, esp32p4]
  v6.1-pre: [esp32h21, esp32h4, esp32s31]

versions:
  - {version: release/v6.1, status: service, ci: full, targets: v5.5, preview: v6.1-pre, released: "2026-08-27"}
  - {version: release/v5.5, status: maintenance, ci: pr, targets: v5.5, preview: v5.5-pre, released: "2025-07-21"}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `version` | yes | The name `app_config.yml`, the build folders and `manage_idf.sh` use: a release branch (`release/v6.1`) or a tag (`v6.0.3`) |
| `ref` | no | The git branch or tag cloned; default: `version` |
| `status` | yes | `service`, `maintenance`, `eol` or `preview` (see [Support periods](#support-periods)) |
| `ci` | yes | `pr`: built on every CI run; `full`: built on tags, schedules and manual runs only; `none`: never built by CI. Exactly one version is `pr` |
| `targets` | yes | A target set: the chips the version supports as stable |
| `preview` | no | A target set: the chips it supports as preview |
| `released` | yes | The date of the x.y.0 release, quoted: `"2026-08-27"` |

Each entry stays on one line, as a flow mapping, and each target set on one line. That keeps a new version a
one-line change and lets `idf_versions.py` read the file without PyYAML (the Python of macOS has none);
`check` reads it both ways when PyYAML is there and fails if they disagree.

A version the file does not list, such as a tag or `master`, still works everywhere: it is cloned as a git ref,
with a warning, and its targets are not checked. A tag such as `v6.0.3` takes its status and targets from the
`release/v6.0` entry and is cloned as `v6.0.3`.

## Adding a version

1. Add one line at the top of `versions:`, normally with `ci: full`, and a target set when the chips changed
   (`tools/idf_py_actions/constants.py` of the release tag lists `SUPPORTED_TARGETS` and `PREVIEW_TARGETS`).
2. `python3 idf_versions.py check`, then `./tests/test_scripts.sh`.
3. Projects pick it up when they bump the `scripts` submodule: `manage_idf.sh install release/v6.2` and
   `available` know it, and an app that lists it in `idf_versions` is built by CI on tags and schedules.
4. Once the projects build and run on it, move `ci: pr` to it (and the old one to `full`) so pull requests
   build the new version.

When a version leaves service or reaches end of life, change its `status`; `check` warns when a status is behind
the support policy for today's date. An `eol` version cannot have `ci: pr` or `full`.

## Support periods

Espressif supports each major or minor release for 30 months from its x.y.0 release: 12 months of service (bug
fixes, recommended for new work), then 18 months of maintenance (high-severity and security fixes only), then end
of life ([SUPPORT_POLICY.md](https://github.com/espressif/esp-idf/blob/master/SUPPORT_POLICY.md)). Espressif no
longer has long-term-support releases: every release gets the same 30 months.

`python3 idf_versions.py get release/v5.5 eol` prints the month a version reaches end of life by that rule.

## What CI builds

`generate_matrix.py --ci-scope` and `idf_versions.py matrix --scope` pick the versions of a CI run:

| Scope | When (`auto`) | Versions per app |
| --- | --- | --- |
| `pr` | pull requests, pushes to a branch | the app's version with `ci: pr`, else the app's first version |
| `full` | tags, schedules, manual runs, releases | every version the app lists |

So an app that lists `["release/v5.5", "release/v6.1"]` builds one version on each pull request and both on a
release tag and on the weekly schedule. `generate_matrix.py` also drops a combination whose `metadata.target` the
version does not support, with a warning. See [Using in CI](ci.md).

## idf_versions.py

```bash
python3 idf_versions.py list [--format table|names|json|tsv] [--scope pr|full|all]
python3 idf_versions.py get <version> <version|ref|status|ci|targets|preview|released|eol>
python3 idf_versions.py matrix [--scope pr|full|all|auto] [--target <chip>]   # GitHub Actions matrix (JSON)
python3 idf_versions.py scope [--event <name>] [--ref <ref>]                  # pr or full
python3 idf_versions.py default                                               # the ci: pr version
python3 idf_versions.py check
```

`--file` (or `IDF_VERSIONS_FILE`) reads another file. `matrix` rows carry `idf_version`, `idf_ref`,
`idf_status`, `idf_version_docker` and `idf_version_file`, the same names as the rows of
[generate_matrix.py](generate-matrix.md), so a workflow that builds without `app_config.yml` (one
`idf.py` build per chip) can use it directly.
