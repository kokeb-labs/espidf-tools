# Changelog

All notable changes to the scripts in this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A change that a project using the scripts must act on
(a removed option, a renamed script, a changed `app_config.yml` key) goes under a `### Breaking` heading and makes
the next release a major one.

## [Unreleased]

### Added

- `idf_versions.yml`: every ESP-IDF version the scripts know, one line each (git ref, stable and preview chips,
  support status, release date, CI use), and `idf_versions.py` to list, query, check it and turn it into a
  GitHub Actions matrix. Adding a version is one line.
- `manage_idf.sh available`, `verify` and `uninstall` (`clean` stays as the same command); `install` takes
  versions, `--targets`, `--shallow`; `uninstall --python-env`; `ESP_IDF_ROOT` and `ESP_IDF_GIT_URL`.
- `generate_matrix.py --ci-scope pr|full|auto|all`: one ESP-IDF version per app on pull requests and branch
  pushes, every version on tags, schedules and manual runs (`auto` uses the event table of
  `idf_versions.py scope`, `pr` for an event it does not name); `ci: none` versions are never built. Scoped
  rows gain `idf_ref` and `idf_status`, a version that does not support `metadata.target` is dropped with a
  warning, and a matrix left empty that way is an error naming the target.
- Tests for all of the above, and a check that no script uses bash 4, BSD-incompatible or `set -e`-unsafe
  constructs.

### Changed

- `build_app.sh` stops with an error when the exported ESP-IDF is another major.minor than the version asked
  for. Before, it built with whatever was exported, in a folder named for the version asked for.
- `manage_idf.sh install` and `setup_common.sh install_esp_idf` without any version in `app_config.yml` install
  the `ci: pr` version of `idf_versions.yml` (release/v5.5 today) instead of a fixed release/v5.5.
- `generate_matrix.py --validate` also warns on ESP-IDF versions `idf_versions.yml` does not list.
- `generate_matrix.py` without `--ci-scope` is unchanged: same rows, same fields, no target check, and the
  default version stays release/v5.5 (`tests/test_scripts.sh` compares it with the 1.0.0 output).
- The tool map shows the two ways in (a terminal, CI), labels every arrow and points each one from the caller to
  what it runs or reads.

### Fixed

- `manage_idf.sh --project-path` failed with "bad substitution" on every bash (`${!((i+1))}`).
- `manage_idf.sh update` (and `setup_repo.sh`, which updates an existing checkout) could not move to a tag or branch that
  appeared after the clone, nor move a shallow checkout at all: the fetch had no refspec.
- `manage_idf.sh uninstall` removed the default version when the default symlink had a trailing slash or a
  relative target, and `list` did not mark it; both now compare resolved paths.
- `manage_idf.sh install <version>` ignored the version, and `install` and `update` installed the tools for
  esp32c6 whatever `metadata.target` said.
- `config_loader.sh` without yq used `head -n -1`, which BSD `head` (macOS) rejects, and `((index++))`, which
  stops a `set -e` script when the index is 0; the same increments are gone from the other scripts.
- The tab completion offered ESP-IDF v5.1, v5.0 and v4.4; it now offers the versions of `idf_versions.yml`.

## [1.0.0] - 2026-11-05

First release of `kokeb-labs/espidf-tools`.

### Added

- `build_app.sh`, `flash_app.sh`, `idf_flash_monitor.sh`, `manage_idf.sh`, `manage_logs.sh`, `detect_ports.sh`,
  `watch_serial_port.sh`: build, flash, monitor and log every app of a multi-app ESP-IDF project, each app, build
  type and ESP-IDF version in its own build folder.
- `config_loader.sh`, `generate_matrix.py`, `get_app_info.py`: read `app_config.yml`, for the shell scripts, for
  CMake and for the GitHub Actions matrix that `ru-build.yml` in
  [ci-tools](https://github.com/kokeb-labs/ci-tools) builds.
- `setup_basic.sh`, `setup_repo.sh`, `setup_common.sh`, `setup_tab_completion.sh`, `esp32_completion.sh`: project
  set-up and shell completion.
- Script tests (`tests/test_scripts.sh`) on Ubuntu and macOS, the documentation site, and the DCO and
  organisation-standard checks behind one CI gate.
