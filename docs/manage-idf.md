# manage_idf.sh

Install, list, verify, switch and remove the ESP-IDF versions a project needs. The versions it knows (git ref,
chips, support status) come from [idf_versions.yml](idf-versions.md).

```bash
./scripts/manage_idf.sh <command> [version...] [--targets <chips>] [--shallow] [--force] [--python-env] \
    [--project-path <path>]
```

## Commands

| Command | Does |
| --- | --- |
| `install [version...]` | Clones each version (its `ref` in `idf_versions.yml`, with submodules) into `~/esp/esp-idf-<version>` and runs its `install.sh` for the chips of `--targets`, else `metadata.target`, else `esp32c6`. With no version, installs every version in `metadata.idf_versions` and points `~/esp/esp-idf` at the first; with versions, sets the default only when there is none. An existing version is left alone; `--force` deletes and re-clones it |
| `available` | Every version of `idf_versions.yml`: ref, status, CI use, release date, chips; `*` marks the installed ones |
| `list` | The versions installed under `~/esp` |
| `export <version>` | Sources that version's `export.sh` in the script's own shell |
| `switch <version>` | Points the `~/esp/esp-idf` symlink at the version |
| `update <version>` | Fetches the ref, fast-forwards a branch (a tag stays), updates the submodules, then `install.sh` for the chips as in `install` |
| `verify <version>` | Checks the installed version: the folder, the ESP-IDF version in its sources against the name, `export.sh`, and `idf.py --version` after `export.sh` (in a child shell). Exit status 1 when a check fails |
| `uninstall <version>` | Deletes the version's folder; refuses the default one. `--python-env` also deletes its Python environment under `$IDF_TOOLS_PATH/python_env` unless another installed checkout has the same major.minor. `clean` is the same command |
| `status` | The current ESP-IDF environment, the tools folder and the default |

With no command, or an unknown one, it prints the usage on stderr and exits with status 2; `--help` prints it on
stdout and exits 0. An option that needs a value and has none (`--project-path`, `--targets`) exits with status 1.

| Option | Commands | Meaning |
| --- | --- | --- |
| `--targets <t1,t2>` | `install`, `update` | Chips to install tools for, comma-separated (`install.sh` takes the same list) |
| `--shallow` | `install`, `update` | Clone only the tip of the ref and of each submodule: about a third of the disk and download. `update` of a shallow branch still fast-forwards |
| `--force` | `install` | Delete and re-clone an existing version |
| `--python-env` | `uninstall` | Also delete the version's Python environment |
| `--project-path <path>` | all | The project, when the scripts are not in `<project>/scripts` |

`install` warns, and goes on, when a version is not in `idf_versions.yml` (it is cloned as a git ref), when it is
end of life, and when a chip is a preview target of the version or not a target of it at all.

## Where things go

| What | Where | Change it with |
| --- | --- | --- |
| ESP-IDF checkouts | `~/esp/esp-idf-<version>` | `ESP_IDF_ROOT` (the folder instead of `~/esp`) |
| Default symlink | `~/esp/esp-idf` | `ESP_IDF_ROOT` |
| Toolchains, Python environments | `~/.espressif` | `IDF_TOOLS_PATH` (ESP-IDF's own variable) |
| Clone URL | `https://github.com/espressif/esp-idf.git` | `ESP_IDF_GIT_URL` (a mirror) |

The folder name replaces every character other than letters, digits, `.`, `_` and `-` with `-`:
`release/v5.5` is installed in `~/esp/esp-idf-release-v5.5`.

`switch`, `update`, `uninstall`, `verify` and `export` also find a version installed under the older name with `/`
replaced by `_` (`~/esp/esp-idf-release_v5.5`), so machines set up by earlier versions of these scripts keep
working. `list` and `status` show both names as `release/v5.5`.

Toolchains in `$IDF_TOOLS_PATH/tools` are shared between ESP-IDF versions, so `uninstall` leaves them. To try a
version without touching the usual folders, point both variables at a scratch folder and delete it afterwards:

```bash
ESP_IDF_ROOT=/tmp/idf-try IDF_TOOLS_PATH=/tmp/idf-try/tools \
    ./scripts/manage_idf.sh install release/v6.1 --shallow --targets esp32c6
ESP_IDF_ROOT=/tmp/idf-try IDF_TOOLS_PATH=/tmp/idf-try/tools ./scripts/manage_idf.sh verify release/v6.1
rm -rf /tmp/idf-try
```

## Using an installed version

`build_app.sh` exports the right version itself when `idf.py` is not on the `PATH`, and stops with an error when
the exported ESP-IDF is another major.minor than the version asked for. In an interactive shell, source the
version directly:

```bash
. ~/esp/esp-idf-release-v5.5/export.sh
```

`export` runs in a child process, so it cannot change the calling shell.
