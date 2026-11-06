# Changelog

All notable changes to the scripts in this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A change that a project using the scripts must act on
(a removed option, a renamed script, a changed `app_config.yml` key) goes under a `### Breaking` heading and makes
the next release a major one.

## [Unreleased]

### Changed

- The tool map shows the two ways in (a terminal, CI), labels every arrow and points each one from the caller to
  what it runs or reads.

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
