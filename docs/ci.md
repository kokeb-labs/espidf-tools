# Using in CI

How GitHub Actions builds every app with these scripts, through the reusable workflow in ci-tools.

[ci-tools](https://kokeb-labs.github.io/ci-tools/) `ru-build.yml` runs, for a caller that pins
`@v1`:

1. `generate_matrix.py` for the matrix, with `--ci-scope auto` when the scripts have it (see below);
2. for each entry, inside the `espressif/idf:<idf_version_docker>` image,
   `build_app.sh --project-path <project_dir> <app> <build_type> <idf_version>`;
3. an upload of `<project_dir>/build*` (the `builds/` folder) as `fw-<app>-<idf>-<build type>`;
4. on pull requests, a size table from each build's `size.info` and `size.txt`.

The workflow requires `generate_matrix.py`, `build_app.sh` and `config_loader.sh` in the tools folder, and
installs `requirements.txt` when it is there.

## The caller

```yaml
jobs:
  build:
    uses: kokeb-labs/ci-tools/.github/workflows/ru-build.yml@v1
    permissions:
      contents: read
      pull-requests: write
    with:
      project_dir: examples/esp32
      project_tools_dir: examples/esp32/scripts
```

Inputs, permissions and failure modes are on the
[ru-build page](https://kokeb-labs.github.io/ci-tools/latest/ru-build/).

## Which ESP-IDF versions a run builds

List every version an app supports in `app_config.yml`; [idf_versions.yml](idf-versions.md) decides how many a
run builds, so CI minutes stay low without editing each project:

| Run | Scope | ESP-IDF versions per app |
| --- | --- | --- |
| Tag push, schedule, manual run, release, repository dispatch | `full` | every version the app lists, except `ci: none` ones |
| Every other event: pull request, push to a branch, merge queue | `pr` | the one with `ci: pr` (else the app's first without `ci: none`) |

A project that wants the full set on a schedule adds one to its caller workflow:

```yaml
on:
  schedule:
    - cron: "17 3 * * 1"   # Mondays 03:17 UTC
```

To see what each kind of run builds:

```bash
python3 examples/esp32/scripts/generate_matrix.py --project-path examples/esp32 --ci-scope pr
python3 examples/esp32/scripts/generate_matrix.py --project-path examples/esp32 --ci-scope full
```

## Keep the matrix and the build on the same file

The workflow runs `generate_matrix.py` without `--project-path`, so the matrix comes from
`examples/esp32/app_config.yml` (from the repository root) or from `app_config.yml` above the scripts. Keep the
project in `examples/esp32` with the scripts in `examples/esp32/scripts`, the Kokeb Labs layout, and both read the same
file.

## Check locally what CI will build

```bash
python3 examples/esp32/scripts/generate_matrix.py --project-path examples/esp32 --format yaml
./examples/esp32/scripts/build_app.sh combinations
```
