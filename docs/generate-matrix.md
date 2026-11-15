# generate_matrix.py

Turn `app_config.yml` into the build matrix of a GitHub Actions job: one entry per app, ESP-IDF version and build
type.

```bash
python3 scripts/generate_matrix.py                         # JSON on stdout
python3 scripts/generate_matrix.py --validate --verbose    # check the file first
python3 scripts/generate_matrix.py --filter gpio_test --format yaml
python3 scripts/generate_matrix.py --ci-scope pr                # what a pull request builds
```

## Options

<!-- generated: options-generate-matrix -->
| Argument | Values | Default | Description |
| --- | --- | --- | --- |
| `--help` / `-h` | flag | - | Show help message |
| `--output` / `-o` | value | - | Output file path |
| `--format` / `-f` | `json`, `yaml` | `json` | Output format |
| `--filter` | value | - | Filter output for specific app |
| `--verbose` / `-v` | flag | - | Verbose output |
| `--validate` | flag | - | Validate configuration |
| `--project-path` / `-p` | value | - | Path to project directory containing app_config.yml |
| `--ci-scope` | `pr`, `full`, `all`, `auto` | `all` | Versions per app: pr (the ci: pr one of idf_versions.yml), full (every one but ci: none), auto (from GITHUB_EVENT_NAME and GITHUB_REF), all (default: every listed version, idf_versions.yml not read) |
<!-- /generated -->

Without `--project-path` the script looks for `examples/esp32/app_config.yml`, `app_config.yml`,
`../app_config.yml`, `../../examples/esp32/app_config.yml` (all from the current directory) and finally
`app_config.yml` in the folder above the script, and uses the first that exists.

## Output

```json
{"include": [
  {"idf_version": "release/v5.5", "idf_version_docker": "release-v5.5", "idf_version_file": "release_v5_5",
   "build_type": "Debug", "app_name": "gpio_test", "target": "esp32c6", "config_source": "global",
   "idf_ref": "release/v5.5", "idf_status": "maintenance"}
]}
```

Without `--ci-scope` (the default, `all`) the output is exactly that of espidf-tools 1.0.0: no `idf_ref` or
`idf_status`, every listed version, and `idf_versions.yml` is not read.

| Field | Meaning |
| --- | --- |
| `idf_version` | As written in `app_config.yml`; passed to `build_app.sh` |
| `idf_ref` | With `--ci-scope`: the git ref to clone, the version's `ref` in [idf_versions.yml](idf-versions.md), else `idf_version` |
| `idf_status` | With `--ci-scope`: `service`, `maintenance`, `eol` or `preview` from `idf_versions.yml`; `unknown` for a version it does not list |
| `idf_version_docker` | `/` replaced by `-`: the `espressif/idf` image tag and the artifact name |
| `idf_version_file` | `/` and `.` replaced by `_`: the build folder suffix |
| `build_type`, `app_name`, `target` | The combination |
| `config_source` | `app` when the app overrides `idf_versions` or `build_types`, else `global` |

## Rules

1. Apps with `ci_enabled: false` are skipped.
2. Each app uses its own `idf_versions`, or `metadata.idf_versions`.
3. Build types: the app's flat `build_types` list for every version; or its nested list by position; or
   `metadata.build_types` by position; `Debug` and `Release` when a position has no list.
4. `--ci-scope` (see [ESP-IDF versions](idf-versions.md#what-ci-builds)): `pr` keeps, per app, its version
   with `ci: pr` in `idf_versions.yml`, else its first version without `ci: none`; `full` keeps every version
   but those with `ci: none`; `auto` picks `full` or `pr` from `GITHUB_EVENT_NAME` and `GITHUB_REF`; `all`, the
   default, keeps every version and reads nothing from `idf_versions.yml`. Two spellings of one version
   (`release/v5.5` and `v5.5.1`) both count as its `ci: pr` version.
5. `metadata.target`, default `esp32c6`. With `--ci-scope`, a version of `idf_versions.yml` that supports the
   target neither as stable nor as preview is dropped for that app, with a warning on standard error; when that
   leaves the matrix empty, the script exits with status 1 and says which target and versions.
6. Entries matching an item of `ci_config.exclude_combinations` on every key are dropped.

`--validate` fails on a missing `metadata` or `apps` section, an empty `apps`, or `build_types` / `idf_versions`
that are not lists of strings, and warns on missing defaults, descriptions or source files and on ESP-IDF
versions `idf_versions.yml` does not list. `--validate` and
`--verbose` print their messages on standard output before the matrix, so leave them out where the output is
parsed as JSON (use `--output` to write the matrix to a file instead).
