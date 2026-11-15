#!/bin/bash
# Behaviour tests for manage_idf.sh, manage_logs.sh, config_loader.sh and get_app_info.py.
#
# Plain bash (3.2 or later), no ESP-IDF, network or serial port needed; runs on Linux (GNU tools) and macOS
# (BSD tools). Every test works in its own temporary folder. Exit status is the number of failed tests.
#
#   ./tests/test_scripts.sh            all tests
#   ./tests/test_scripts.sh logs       only tests whose name contains "logs"
#
# get_app_info.py tests need python3 with PyYAML and are skipped without it.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${1:-}"
PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()

# ---------------------------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------------------------

fail() {
    echo "    FAIL: $*"
    return 1
}

# assert_contains <haystack> <needle>
assert_contains() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    fail "expected output to contain '$2'"$'\n'"--- output ---"$'\n'"$1"$'\n'"--------------"
}

# assert_not_contains <haystack> <needle>
assert_not_contains() {
    case "$1" in
        *"$2"*)
            fail "expected output not to contain '$2'"$'\n'"--- output ---"$'\n'"$1"$'\n'"--------------"
            return 1
            ;;
    esac
    return 0
}

# assert_eq <actual> <expected>
assert_eq() {
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

# A project folder with the scripts in <project>/scripts, as the scripts expect
make_project() {
    local project="$1"
    mkdir -p "$project/scripts"
    cp "$ROOT"/*.sh "$ROOT"/*.py "$project/scripts/"
    cat > "$project/app_config.yml" <<'EOF'
---
version: "1.0"
metadata:
  default_app: "gpio_test"
  default_build_type: "Debug"
  target: "esp32c6"
  idf_versions: ["release/v5.5", "release/v5.4"]
  build_types: [["Debug", "Release"], ["Debug"]]

apps:
  gpio_test:
    description: "GPIO test"
    source_file: "GpioTest.cpp"
    category: "peripheral"
    tags: ["gpio", "io"]
  adc_test:
    description: "ADC test"
    source_files: ["AdcTest.cpp", "AdcHelpers.cpp"]
    idf_versions: ["release/v5.4"]
    build_types: ["Release"]
EOF
}

# Set a file's modification time: touch_at <YYYYMMDDhhmm> <file>
touch_at() {
    touch -t "$1" "$2"
}

# A fake yq that answers --version like mikefarah yq v4 and prints "null" for every query, which is what yq
# prints for a key that is not in the file.
make_null_yq() {
    mkdir -p "$1"
    cat > "$1/yq" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
    echo "yq (https://github.com/mikefarah/yq/) version v4.44.3"
    exit 0
fi
echo null
EOF
    chmod +x "$1/yq"
}

run_test() {
    local name="$1"
    if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
        return 0
    fi
    TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/espidf-tools-test.XXXXXX")"
    echo "  $name"
    local status=0
    ( cd "$TEST_TMP" && "$name" ) || status=$?
    rm -rf "$TEST_TMP"
    if [ $status -eq 0 ]; then
        PASSED=$((PASSED + 1))
    elif [ $status -eq 200 ]; then
        echo "    skipped"
        SKIPPED=$((SKIPPED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
}

skip() {
    echo "    skip: $*"
    exit 200
}

# ---------------------------------------------------------------------------------------------------------------
# manage_idf.sh: folder names
# ---------------------------------------------------------------------------------------------------------------

test_idf_switch_finds_install_folder_name() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5"
    local out
    out=$("$ROOT/manage_idf.sh" switch release/v5.5 2>&1) || fail "switch failed: $out" || return 1
    assert_eq "$(readlink "$HOME/esp/esp-idf")" "$HOME/esp/esp-idf-release-v5.5"
}

test_idf_switch_finds_legacy_underscore_name() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release_v5.4"
    local out
    out=$("$ROOT/manage_idf.sh" switch release/v5.4 2>&1) || fail "switch failed: $out" || return 1
    assert_eq "$(readlink "$HOME/esp/esp-idf")" "$HOME/esp/esp-idf-release_v5.4"
}

test_idf_clean_removes_install_folder_name() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5" "$HOME/esp/esp-idf-release-v5.4"
    ln -s "$HOME/esp/esp-idf-release-v5.5" "$HOME/esp/esp-idf"
    local out
    out=$("$ROOT/manage_idf.sh" clean release/v5.4 2>&1) || fail "clean failed: $out" || return 1
    [ ! -d "$HOME/esp/esp-idf-release-v5.4" ] || fail "folder still there"
}

test_idf_clean_refuses_default_version() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5"
    ln -s "$HOME/esp/esp-idf-release-v5.5" "$HOME/esp/esp-idf"
    if "$ROOT/manage_idf.sh" clean release/v5.5 >/dev/null 2>&1; then
        fail "clean of the default version succeeded"
        return 1
    fi
    [ -d "$HOME/esp/esp-idf-release-v5.5" ] || fail "default version was removed"
}

test_idf_missing_version_reports_install_folder_name() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp"
    local out
    if out=$("$ROOT/manage_idf.sh" update release/v5.3 2>&1); then
        fail "update of a missing version succeeded"
        return 1
    fi
    assert_contains "$out" "esp-idf-release-v5.3"
}

test_idf_status_names_both_folder_styles() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5" "$HOME/esp/esp-idf-release_v5.4"
    ln -s "$HOME/esp/esp-idf-release_v5.4" "$HOME/esp/esp-idf"
    local out
    out=$("$ROOT/manage_idf.sh" status 2>&1) || fail "status failed: $out" || return 1
    assert_contains "$out" "Default ESP-IDF version: release/v5.4" || return 1
    assert_contains "$out" "release/v5.5" || return 1
    assert_not_contains "$out" "- release_v5.4"
}

test_idf_no_command_prints_usage_and_exits_2() {
    export HOME="$TEST_TMP"
    local out status=0
    out=$("$ROOT/manage_idf.sh" 2>&1) || status=$?
    assert_eq "$status" "2" || return 1
    assert_contains "$out" "No command specified" || return 1
    assert_contains "$out" "Usage: ./manage_idf.sh" || return 1
    assert_not_contains "$out" "command not found"
}

test_idf_unknown_command_exits_2() {
    export HOME="$TEST_TMP"
    local out status=0
    out=$("$ROOT/manage_idf.sh" bogus 2>&1) || status=$?
    assert_eq "$status" "2" || return 1
    assert_contains "$out" "Unknown command: bogus" || return 1
    assert_not_contains "$out" "command not found"
}

test_idf_help_exits_0() {
    local out
    out=$("$ROOT/manage_idf.sh" --help) || fail "--help exited non-zero" || return 1
    assert_contains "$out" "Usage: ./manage_idf.sh"
}

# ---------------------------------------------------------------------------------------------------------------
# manage_idf.sh: options, the versions file, install / verify / uninstall with a fake git
# ---------------------------------------------------------------------------------------------------------------

# A fake git on the PATH: `clone` makes a checkout whose tools/cmake/version.cmake matches the ref, with an
# install.sh and an export.sh that log what they were called with; `-C <dir> describe` answers the ref.
make_fake_git() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/git" <<'EOF'
#!/bin/bash
log="${FAKE_GIT_LOG:?}"
if [ "$1" = "-C" ]; then
    echo "fake-describe"
    exit 0
fi
if [ "$1" != "clone" ]; then
    echo "git $*" >> "$log"
    exit 0
fi
echo "git $*" >> "$log"
ref=""
prev=""
for a in "$@"; do
    [ "$prev" = "--branch" ] && ref="$a"
    prev="$a"
    dir="$a"
done
mm=$(echo "$ref" | sed -n 's/.*v\([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
set -- $mm
mkdir -p "$dir/tools/cmake" "$dir/bin"
printf 'set(IDF_VERSION_MAJOR %s)\nset(IDF_VERSION_MINOR %s)\nset(IDF_VERSION_PATCH 0)\n' "${1:-0}" "${2:-0}" \
    > "$dir/tools/cmake/version.cmake"
printf '#!/bin/bash\necho "install.sh $*" >> "%s"\n' "$log" > "$dir/install.sh"
printf '#!/bin/bash\necho "ESP-IDF v%s.%s-fake"\n' "${1:-0}" "${2:-0}" > "$dir/bin/idf.py"
printf 'export PATH="%s/bin:$PATH"\n' "$dir" > "$dir/export.sh"
chmod +x "$dir/install.sh" "$dir/bin/idf.py"
EOF
    chmod +x "$bin/git"
}

test_idf_project_path_option_bash32() {
    # ${!((i+1))} is a syntax error in every bash; the option must work on the bash 3.2 of macOS.
    export HOME="$TEST_TMP"
    make_project "$TEST_TMP/proj"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5"
    local out
    out=$(/bin/bash "$ROOT/manage_idf.sh" --project-path "$TEST_TMP/proj" switch release/v5.5 2>&1) \
        || fail "switch with --project-path failed: $out" || return 1
    assert_not_contains "$out" "bad substitution" || return 1
    assert_eq "$(readlink "$HOME/esp/esp-idf")" "$HOME/esp/esp-idf-release-v5.5"
}

test_idf_option_without_value_fails_cleanly() {
    export HOME="$TEST_TMP"
    local out status=0
    out=$(/bin/bash "$ROOT/manage_idf.sh" list --project-path 2>&1) || status=$?
    assert_eq "$status" "1" || return 1
    assert_contains "$out" "--project-path requires a value" || return 1
    assert_not_contains "$out" "bad substitution"
}

test_idf_available_lists_versions_file() {
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/esp/esp-idf-release-v5.5"
    local out v
    out=$("$ROOT/manage_idf.sh" available 2>&1) || fail "available failed: $out" || return 1
    for v in $(python3 "$ROOT/idf_versions.py" list --format names); do
        assert_contains "$out" "$v" || return 1
    done
    assert_contains "$out" "* release/v5.5" || return 1
    assert_contains "$out" "  release/v6.1"
}

test_idf_install_explicit_version_shallow_with_targets() {
    export HOME="$TEST_TMP"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install release/v6.1 --shallow \
        --targets esp32c6,esp32s3 2>&1) || fail "install failed: $out" || return 1
    local log
    log=$(cat "$FAKE_GIT_LOG")
    assert_contains "$log" "--branch release/v6.1" || return 1
    assert_contains "$log" "--depth 1 --shallow-submodules" || return 1
    assert_contains "$log" "https://github.com/espressif/esp-idf.git $HOME/esp/esp-idf-release-v6.1" || return 1
    assert_contains "$log" "install.sh esp32c6,esp32s3" || return 1
    # No default yet: the first install becomes it.
    assert_eq "$(readlink "$HOME/esp/esp-idf")" "$HOME/esp/esp-idf-release-v6.1"
}

test_idf_install_from_app_config_uses_its_target() {
    export HOME="$TEST_TMP"
    make_project "$TEST_TMP/proj"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" "$TEST_TMP/proj/scripts/manage_idf.sh" install 2>&1) \
        || fail "install failed: $out" || return 1
    local log
    log=$(cat "$FAKE_GIT_LOG")
    assert_contains "$log" "--branch release/v5.5" || return 1
    assert_contains "$log" "--branch release/v5.4" || return 1
    assert_not_contains "$log" "--depth" || return 1
    assert_contains "$log" "install.sh esp32c6" || return 1
    assert_eq "$(readlink "$HOME/esp/esp-idf")" "$HOME/esp/esp-idf-release-v5.5"
}

test_idf_install_warns_unknown_version_and_target() {
    export HOME="$TEST_TMP"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install v9.9.9 2>&1) || fail "install failed: $out" || return 1
    assert_contains "$out" "v9.9.9 is not in idf_versions.yml" || return 1
    out=$(PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install release/v5.4 --targets esp32s31 2>&1) \
        || fail "install failed: $out" || return 1
    assert_contains "$out" "esp32s31 is not a target of release/v5.4"
}

test_idf_install_with_esp_idf_root() {
    export HOME="$TEST_TMP"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" ESP_IDF_ROOT="$TEST_TMP/elsewhere" "$ROOT/manage_idf.sh" install release/v6.0 2>&1) \
        || fail "install failed: $out" || return 1
    [ -d "$TEST_TMP/elsewhere/esp-idf-release-v6.0" ] || fail "not installed under ESP_IDF_ROOT" || return 1
    [ ! -e "$HOME/esp" ] || fail "$HOME/esp was used"
}

test_idf_verify_ok_and_mismatch() {
    export HOME="$TEST_TMP"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install release/v6.1 >/dev/null 2>&1 || fail "install" || return 1
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" verify release/v6.1 2>&1) || fail "verify failed: $out" || return 1
    assert_contains "$out" "sources are ESP-IDF 6.1" || return 1
    assert_contains "$out" "ESP-IDF release/v6.1: OK" || return 1
    # A folder holding another version than its name says
    sed -i.bak 's/MINOR 1/MINOR 0/' "$HOME/esp/esp-idf-release-v6.1/tools/cmake/version.cmake"
    if out=$(PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" verify release/v6.1 2>&1); then
        fail "verify of a mismatched folder succeeded"
        return 1
    fi
    assert_contains "$out" "sources are ESP-IDF 6.0, not 6.1"
}

test_idf_uninstall_python_env() {
    export HOME="$TEST_TMP"
    export IDF_TOOLS_PATH="$TEST_TMP/tools"
    make_fake_git "$TEST_TMP/bin"
    export FAKE_GIT_LOG="$TEST_TMP/git.log"
    PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install release/v5.5 >/dev/null 2>&1 || fail "install" || return 1
    PATH="$TEST_TMP/bin:$PATH" "$ROOT/manage_idf.sh" install release/v6.1 >/dev/null 2>&1 || fail "install" || return 1
    mkdir -p "$IDF_TOOLS_PATH/python_env/idf6.1_py3.12_env" "$IDF_TOOLS_PATH/python_env/idf5.5_py3.12_env"
    local out
    out=$("$ROOT/manage_idf.sh" uninstall release/v6.1 --python-env 2>&1) || fail "uninstall failed: $out" || return 1
    [ ! -d "$HOME/esp/esp-idf-release-v6.1" ] || fail "checkout still there" || return 1
    [ ! -d "$IDF_TOOLS_PATH/python_env/idf6.1_py3.12_env" ] || fail "6.1 Python env still there" || return 1
    [ -d "$IDF_TOOLS_PATH/python_env/idf5.5_py3.12_env" ] || fail "5.5 Python env removed"
}

test_idf_helpers_major_minor() {
    local out
    out=$(bash -c 'source "$1/setup_common.sh"
        idf_major_minor release/v6.1; idf_major_minor v6.0.3; idf_major_minor v5.5-rc1; idf_major_minor master
        echo "ref:$(idf_ref_for_version release/v5.5) $(idf_ref_for_version v6.0.3) $(idf_ref_for_version master)"
        echo "default:$(idf_default_version)"' _ "$ROOT" 2>&1)
    assert_eq "$out" "6.1
6.0
5.5
ref:release/v5.5 v6.0.3 master
default:$(python3 "$ROOT/idf_versions.py" default)"
}

# ---------------------------------------------------------------------------------------------------------------
# idf_versions.py and generate_matrix.py --ci-scope
# ---------------------------------------------------------------------------------------------------------------

test_versions_file_checks_clean() {
    local out
    out=$(python3 "$ROOT/idf_versions.py" check 2>&1) || fail "check failed: $out" || return 1
    # Both readers: the one-line reader alone must give the same as PyYAML (when installed).
    local a b
    a=$(IDF_VERSIONS_NO_YAML=1 python3 "$ROOT/idf_versions.py" list --format json)
    b=$(python3 "$ROOT/idf_versions.py" list --format json)
    assert_eq "$a" "$b"
}

test_versions_file_check_rejects_bad_files() {
    local f="$TEST_TMP/v.yml" out
    printf -- '---\ntarget_sets:\n  s: [esp32]\nversions:\n  - {version: a/v1.0, status: service, ci: pr, targets: s, released: "2026-01-01"}\n  - {version: a/v2.0, status: service, ci: pr, targets: nope, released: "2026-01-01"}\n' > "$f"
    if out=$(python3 "$ROOT/idf_versions.py" --file "$f" check 2>&1); then
        fail "check passed a bad file"
        return 1
    fi
    assert_contains "$out" "exactly one version must have ci: pr (found 2)" || return 1
    assert_contains "$out" "unknown target set 'nope'" || return 1
    printf -- '---\ntarget_sets:\n  s: [esp32]\nversions:\n  - version: a/v1.0\n    status: service\n' > "$f"
    if out=$(python3 "$ROOT/idf_versions.py" --file "$f" check 2>&1); then
        fail "check passed a multi-line entry"
        return 1
    fi
    assert_contains "$out" "on one line"
}

test_versions_file_status_warning() {
    local f="$TEST_TMP/v.yml" out
    printf -- '---\ntarget_sets:\n  s: [esp32]\nversions:\n  - {version: a/v1.0, status: service, ci: pr, targets: s, released: "2020-01-01"}\n' > "$f"
    out=$(python3 "$ROOT/idf_versions.py" --file "$f" check 2>&1) || true
    assert_contains "$out" "status is service, the support policy says eol today" || return 1
    assert_not_contains "$out" "an end-of-life version cannot be built by CI"
}

test_versions_scope_for_events() {
    local v="python3 $ROOT/idf_versions.py scope"
    assert_eq "$($v --event pull_request --ref refs/pull/1/merge)" "pr" || return 1
    assert_eq "$($v --event push --ref refs/heads/main)" "pr" || return 1
    assert_eq "$($v --event push --ref refs/tags/v1.2.0)" "full" || return 1
    assert_eq "$($v --event schedule)" "full" || return 1
    assert_eq "$($v --event workflow_dispatch)" "full"
}

test_versions_matrix_scopes() {
    local pr full
    pr=$(python3 "$ROOT/idf_versions.py" matrix --scope pr)
    full=$(python3 "$ROOT/idf_versions.py" matrix --scope full --target esp32c6)
    python3 -c '
import json, sys
pr, full = json.loads(sys.argv[1])["include"], json.loads(sys.argv[2])["include"]
assert len(pr) == 1, pr
assert len(full) >= len(pr), full
assert all(r["target"] == "esp32c6" and r["idf_ref"] for r in full), full
assert pr[0]["idf_version"] in [r["idf_version"] for r in full]
' "$pr" "$full" || fail "unexpected matrices: $pr / $full"
}

matrix_rows() {
    python3 -c '
import json, sys
for e in json.load(sys.stdin)["include"]:
    print(e["app_name"], e["idf_version"], e["idf_ref"], e["build_type"])'
}

test_matrix_ci_scope_pr_and_full() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    local pr full
    pr=$(python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" --ci-scope pr | matrix_rows)
    full=$(python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" --ci-scope full | matrix_rows)
    # gpio_test lists v5.5 (ci: pr) and v5.4: pull requests build v5.5 only. adc_test lists only v5.4: its first.
    assert_eq "$pr" "gpio_test release/v5.5 release/v5.5 Debug
gpio_test release/v5.5 release/v5.5 Release
adc_test release/v5.4 release/v5.4 Release" || return 1
    assert_eq "$full" "gpio_test release/v5.5 release/v5.5 Debug
gpio_test release/v5.5 release/v5.5 Release
gpio_test release/v5.4 release/v5.4 Debug
adc_test release/v5.4 release/v5.4 Release" || return 1
    assert_eq "$(python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" | matrix_rows)" "$full"
}

test_matrix_ci_scope_auto_and_unsupported_target() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    local out err
    out=$(GITHUB_EVENT_NAME=pull_request python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" --ci-scope auto \
        | matrix_rows | wc -l | tr -d ' ')
    assert_eq "$out" "3" || return 1
    sed -i.bak 's/target: "esp32c6"/target: "esp32s31"/' "$TEST_TMP/proj/app_config.yml"
    err=$(python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" 2>&1 >/dev/null)
    out=$(python3 "$ROOT/generate_matrix.py" -p "$TEST_TMP/proj" 2>/dev/null | matrix_rows)
    assert_eq "$out" "" || return 1
    assert_contains "$err" "esp32s31 is not a target of release/v5.5"
}

test_scripts_are_bash32_portable() {
    # Constructs bash 3.2 (macOS) or BSD tools do not have, and ((x++)), which fails under set -e when x is 0.
    local hits
    hits=$(grep -nE '\$\{!\(\(|declare -A|local -A|typeset -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)\}|head -n -[0-9]|\(\([a-z_]+(\+\+|--)\)\)|\[\[ -v ' \
        "$ROOT"/*.sh | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    [ -z "$hits" ] || fail "not portable: $hits"
}

# ---------------------------------------------------------------------------------------------------------------
# config_loader.sh: build_config defaults and the portable mtime sort
# ---------------------------------------------------------------------------------------------------------------

test_config_missing_patterns_with_yq_use_defaults() {
    make_project "$TEST_TMP/proj"
    make_null_yq "$TEST_TMP/bin"
    local out
    out=$(PATH="$TEST_TMP/bin:$PATH" PROJECT_PATH="$TEST_TMP/proj" bash -c '
        source "$1/config_loader.sh"
        get_build_directory gpio_test Debug esp32c6 release/v5.5
        get_project_name gpio_test' _ "$ROOT" 2>/dev/null)
    assert_eq "$out" "$TEST_TMP/proj/builds/build-app-gpio_test-type-Debug-target-esp32c6-idf-release_v5_5
esp32_iid_gpio_test_app"
}

test_config_without_yq_uses_defaults() {
    make_project "$TEST_TMP/proj"
    local out
    out=$(PROJECT_PATH="$TEST_TMP/proj" bash -c '
        source "$1/config_loader.sh"
        check_yq() { return 1; }
        get_build_directory gpio_test Release esp32c6 release/v5.4' _ "$ROOT" 2>/dev/null)
    assert_eq "$out" "$TEST_TMP/proj/builds/build-app-gpio_test-type-Release-target-esp32c6-idf-release_v5_4"
}

test_config_sort_paths_by_mtime_desc() {
    make_project "$TEST_TMP/proj"
    mkdir -p "$TEST_TMP/b/build-old" "$TEST_TMP/b/build-new" "$TEST_TMP/b/build-mid"
    touch_at 202401010000 "$TEST_TMP/b/build-old"
    touch_at 202403010000 "$TEST_TMP/b/build-new"
    touch_at 202402010000 "$TEST_TMP/b/build-mid"
    local out
    out=$(PROJECT_PATH="$TEST_TMP/proj" bash -c '
        source "$1/config_loader.sh"
        find "$2" -maxdepth 1 -type d -name "build-*" | sort_paths_by_mtime_desc' _ "$ROOT" "$TEST_TMP/b" 2>/dev/null)
    assert_eq "$out" "$TEST_TMP/b/build-new
$TEST_TMP/b/build-mid
$TEST_TMP/b/build-old"
}

test_no_gnu_only_find_printf_or_stat_c() {
    # find -printf and a bare stat -c fail on macOS; stat -c is fine only with a stat -f fallback.
    local hits code
    code=$(grep -n -e 'find .*-printf' -e 'stat -c' "$ROOT"/*.sh | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#' || true)
    hits=$(echo "$code" | grep -e 'find .*-printf' || true)
    [ -z "$hits" ] || fail "find -printf in: $hits" || return 1
    hits=$(echo "$code" | grep -e 'stat -c' | grep -v 'stat -f' || true)
    [ -z "$hits" ] || fail "stat -c without stat -f fallback in: $hits"
}

# ---------------------------------------------------------------------------------------------------------------
# manage_logs.sh
# ---------------------------------------------------------------------------------------------------------------

make_logs() {
    make_project "$TEST_TMP/proj"
    mkdir -p "$TEST_TMP/proj/logs"
    LOGS="$TEST_TMP/proj/logs"
    printf 'boot\nE (120) gpio: boom\nI (130) done\n' > "$LOGS/gpio_test_Release_20240101_000000.log"
    printf 'adc line 1\nadc line 2\nadc line 3\n' > "$LOGS/adc_test_Debug_20240201_000000.log"
    touch_at 202401010930 "$LOGS/gpio_test_Release_20240101_000000.log"
    touch_at 202402011015 "$LOGS/adc_test_Debug_20240201_000000.log"
    LOGS_SH="$TEST_TMP/proj/scripts/manage_logs.sh"
}

test_logs_list_shows_dates_and_times() {
    make_logs
    local out
    out=$("$LOGS_SH" list --no-color 2>&1) || fail "list failed: $out" || return 1
    assert_contains "$out" "2024-01-01" || return 1
    assert_contains "$out" "09:30:00" || return 1
    assert_contains "$out" "2024-02-01" || return 1
    assert_not_contains "$out" "Unknown"
}

test_logs_list_filters_by_pattern() {
    make_logs
    local out
    out=$("$LOGS_SH" list gpio --no-color 2>&1) || fail "list failed: $out" || return 1
    assert_contains "$out" "gpio_test_Release" || return 1
    assert_not_contains "$out" "adc_test"
}

test_logs_latest_picks_newest() {
    make_logs
    local out
    out=$("$LOGS_SH" latest --no-color 2>&1) || fail "latest failed: $out" || return 1
    assert_contains "$out" "Latest log file: adc_test_Debug_20240201_000000.log" || return 1
    assert_contains "$out" "adc line 3"
}

test_logs_stats_oldest_newest_and_size() {
    make_logs
    local out
    out=$("$LOGS_SH" stats --no-color 2>&1) || fail "stats failed: $out" || return 1
    assert_contains "$out" "Total log files: 2" || return 1
    assert_contains "$out" "Total size: 70 bytes" || return 1
    assert_contains "$out" "Oldest log: gpio_test_Release_20240101_000000.log (2024-01-01)" || return 1
    assert_contains "$out" "Newest log: adc_test_Debug_20240201_000000.log (2024-02-01)"
}

test_logs_search() {
    make_logs
    local out
    out=$("$LOGS_SH" search boom --no-color 2>&1) || fail "search failed: $out" || return 1
    assert_contains "$out" "Found 1 match(es) in: gpio_test_Release_20240101_000000.log" || return 1
    assert_not_contains "$out" "integer expression"
}

test_logs_tail() {
    make_logs
    local out
    out=$("$LOGS_SH" tail adc_test_Debug_20240201_000000.log 2 2>&1) || fail "tail failed: $out" || return 1
    assert_eq "$out" "adc line 2
adc line 3"
}

test_logs_grep() {
    make_logs
    local out
    out=$("$LOGS_SH" grep gpio_test_Release_20240101_000000.log "E (" 2>&1) || fail "grep failed: $out" || return 1
    assert_eq "$out" "2:E (120) gpio: boom" || return 1
    if "$LOGS_SH" grep gpio_test_Release_20240101_000000.log nothing-here --no-color >/dev/null 2>&1; then
        fail "grep without a match exited 0"
    fi
}

test_logs_no_color() {
    make_logs
    local out
    out=$("$LOGS_SH" list --no-color 2>&1)
    assert_not_contains "$out" $'\033[' || return 1
    out=$(NO_COLOR=1 "$LOGS_SH" list 2>&1)
    assert_not_contains "$out" $'\033['
}

test_logs_help_lists_only_implemented_commands() {
    local help cmd
    help=$("$ROOT/manage_logs.sh" --help)
    assert_not_contains "$help" "--verbose" || return 1
    for cmd in list view search clean stats latest tail grep; do
        assert_contains "$help" "  $cmd" || return 1
        grep -q "\"$cmd\")" "$ROOT/manage_logs.sh" || fail "help lists $cmd, script has no case for it" || return 1
    done
}

# ---------------------------------------------------------------------------------------------------------------
# get_app_info.py
# ---------------------------------------------------------------------------------------------------------------

need_pyyaml() {
    python3 -c 'import yaml' 2>/dev/null || skip "python3 with PyYAML not available"
}

app_info() {
    python3 "$ROOT/get_app_info.py" "$@" --project-path "$TEST_TMP/proj"
}

test_app_info_every_help_command_is_implemented() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    local cmds cmd out
    cmds=$(python3 "$ROOT/get_app_info.py" --help | sed -n '/^COMMANDS:/,/^$/p' | awk 'NR > 1 && NF {print $1}')
    [ -n "$cmds" ] || fail "no commands found in --help" || return 1
    for cmd in $cmds; do
        out=$(app_info "$cmd" gpio_test 2>&1) || fail "$cmd exited non-zero: $out" || return 1
        assert_not_contains "$out" "Unknown command" || return 1
    done
}

test_app_info_values() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    assert_eq "$(app_info source_file adc_test)" "AdcTest.cpp" || return 1
    assert_eq "$(app_info list)" "gpio_test adc_test" || return 1
    assert_eq "$(app_info idf_versions gpio_test)" "release/v5.5 release/v5.4" || return 1
    assert_eq "$(app_info build_types gpio_test)" "release/v5.5: Debug Release
release/v5.4: Debug" || return 1
    assert_eq "$(app_info build_types adc_test)" "release/v5.4: Release" || return 1
    assert_eq "$(app_info tags gpio_test)" "gpio io" || return 1
    assert_eq "$(app_info category gpio_test)" "peripheral" || return 1
    assert_eq "$(app_info category adc_test)" "" || return 1
    assert_eq "$(app_info dependencies gpio_test --format json)" "null"
}

test_app_info_json() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    local out
    out=$(app_info info adc_test --format json) || fail "info failed" || return 1
    python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["name"] == "adc_test", d
assert d["idf_versions"] == ["release/v5.4"], d
assert d["build_types"] == {"release/v5.4": ["Release"]}, d
' "$out" || fail "unexpected json: $out"
}

test_app_info_unknown_app() {
    need_pyyaml
    make_project "$TEST_TMP/proj"
    if app_info info nope >/dev/null 2>&1; then
        fail "info of an unknown app exited 0"
        return 1
    fi
    assert_eq "$(app_info validate nope 2>/dev/null)" "false"
}

# ---------------------------------------------------------------------------------------------------------------

echo "Running script tests on $(uname -s) with bash ${BASH_VERSION}"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
    run_test "$t"
done

echo ""
echo "Passed: $PASSED  Failed: $FAILED  Skipped: $SKIPPED"
if [ $FAILED -gt 0 ]; then
    printf '  failed: %s\n' "${FAILED_NAMES[@]}"
fi
exit $FAILED
