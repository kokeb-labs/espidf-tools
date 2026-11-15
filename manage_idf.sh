#!/bin/bash
# ESP-IDF Version Management Script
# Installs, lists, switches, verifies and removes the ESP-IDF versions a project needs. The versions these scripts
# know (git ref, targets, support status) are in idf_versions.yml next to this script.
#
# Plain bash 3.2 (macOS) or later; Linux and macOS.

set -e  # Exit on any error

# Parse the options first, wherever they are; the rest are the command and its arguments.
FILTERED_ARGS=()
FORCE=false
SHALLOW=false
PYTHON_ENV=false
TARGETS=""
i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    next_index=$((i + 1))
    case "$arg" in
        --project-path|--targets)
            # The value is the next argument; it must exist and not be another option.
            if [[ $next_index -le $# ]] && [[ "${!next_index}" != -* ]]; then
                if [[ "$arg" == "--project-path" ]]; then
                    PROJECT_PATH="${!next_index}"
                else
                    TARGETS="${!next_index}"
                fi
                i=$next_index  # Skip the value we consumed
            else
                echo "ERROR: $arg requires a value" >&2
                echo "Usage: $arg <value>" >&2
                exit 1
            fi
            ;;
        --force) FORCE=true ;;
        --shallow) SHALLOW=true ;;
        --python-env) PYTHON_ENV=true ;;
        --verbose) ;;
        *)
            FILTERED_ARGS+=("$arg")
            ;;
    esac
    i=$((i + 1))
done

# Export PROJECT_PATH if it was set via --project-path flag
if [[ -n "$PROJECT_PATH" ]]; then
    export PROJECT_PATH
fi

# Source the common setup functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_common.sh"

# Replace $@ with filtered arguments for the rest of the script (an empty array is unset in bash 3.2 under set -u)
set -- ${FILTERED_ARGS[@]+"${FILTERED_ARGS[@]}"}

# Print the usage text
show_help() {
    echo "ESP-IDF Version Management Script"
    echo ""
    echo "Usage: ./manage_idf.sh [COMMAND] [VERSION...] [OPTIONS]"
    echo ""
    echo "COMMANDS:"
    echo "  install [version...]        - Install the given versions, else every version in app_config.yml"
    echo "  available                   - The versions idf_versions.yml knows: ref, status, CI use, targets"
    echo "  list                        - List installed ESP-IDF versions"
    echo "  export <version>            - Export ESP-IDF environment for specific version"
    echo "  switch <version>            - Switch default ESP-IDF version"
    echo "  update <version>            - Update specific ESP-IDF version"
    echo "  verify <version>            - Check an installed version: folder, version, export.sh, idf.py"
    echo "  uninstall <version>         - Remove specific ESP-IDF version (clean is the same command)"
    echo "  status                      - Show current ESP-IDF status"
    echo ""
    echo "OPTIONS:"
    echo "  --project-path <path>       - Path to project directory (allows scripts to be placed anywhere)"
    echo "  --targets <t1,t2>           - install/update: chips to install tools for (default: app_config.yml"
    echo "                                metadata.target, else esp32c6)"
    echo "  --shallow                   - install: clone only the tip of the ref (about a third of the disk)"
    echo "  --force                     - install: delete and re-clone an existing version"
    echo "  --python-env                - uninstall: also remove the version's Python environment"
    echo "  --help, -h                  - Show this help message"
    echo ""
    echo "ARGUMENTS:"
    echo "  version                     - ESP-IDF version (e.g., release/v6.1, release/v5.5, v6.0.3)"
    echo ""
    echo "EXAMPLES:"
    echo "  ./manage_idf.sh available                  # What can be installed, and what CI builds"
    echo "  ./manage_idf.sh install                    # Install all required versions"
    echo "  ./manage_idf.sh install release/v6.1 --shallow --targets esp32c6,esp32s3"
    echo "  ./manage_idf.sh install --force            # Force reinstall all versions"
    echo "  ./manage_idf.sh list                       # List installed versions"
    echo "  ./manage_idf.sh verify release/v6.1        # Check an installed version works"
    echo "  ./manage_idf.sh switch release/v5.5        # Set v5.5 as default"
    echo "  ./manage_idf.sh update release/v5.5        # Update v5.5 to latest"
    echo "  ./manage_idf.sh uninstall release/v5.4 --python-env"
    echo ""
    echo "  # Environment setup"
    echo "  . ~/esp/esp-idf-release-v5.5/export.sh     # Source a version in the current shell"
    echo ""
    echo "VERSIONS FILE:"
    echo "  • idf_versions.yml next to this script: one line per version (see docs/idf-versions.md)"
    echo "  • A version it does not list (a tag, master) is cloned as a git ref, with a warning"
    echo ""
    echo "INSTALLATION LOCATIONS:"
    echo "  • ESP-IDF versions: \$ESP_IDF_ROOT/esp-idf-{version} (default ~/esp)"
    echo "  • Default symlink: \$ESP_IDF_ROOT/esp-idf"
    echo "  • Tools: \$IDF_TOOLS_PATH (default ~/.espressif/)"
    echo "  • Python packages: \$IDF_TOOLS_PATH/python_env/"
    echo ""
    echo "TROUBLESHOOTING:"
    echo "  • If installation fails: Check disk space, internet connection"
    echo "  • If export fails: Ensure version is installed first"
    echo "  • If switch fails: Check permissions and existing installations"
    echo "  • For version conflicts: Use --force flag carefully"
    echo ""
}

# Show help if requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

# The chips to install tools for: --targets, else metadata.target of app_config.yml, else esp32c6.
resolve_targets() {
    if [[ -n "$TARGETS" ]]; then
        echo "$TARGETS"
        return 0
    fi
    local target=""
    if [[ -n "${CONFIG_TARGET:-}" ]]; then
        target="$CONFIG_TARGET"
    fi
    echo "${target:-esp32c6}"
}

# Warn about a version idf_versions.yml does not know, an end-of-life one, or a target it does not support.
check_version_and_targets() {
    local version="$1" targets="$2" status supported preview t
    if ! command -v python3 >/dev/null 2>&1; then
        print_warning "python3 not found: $version and its targets are not checked against idf_versions.yml"
        return 0
    fi
    if ! status=$(idf_versions_cmd get "$version" status 2>/dev/null); then
        print_warning "$version is not in idf_versions.yml: cloning it as a git ref, targets unchecked"
        return 0
    fi
    if [[ "$status" == "eol" ]]; then
        print_warning "$version is end of life: no more fixes from Espressif"
    fi
    supported=" $(idf_versions_cmd get "$version" targets 2>/dev/null) "
    preview=" $(idf_versions_cmd get "$version" preview 2>/dev/null) "
    for t in $(echo "$targets" | tr ',' ' '); do
        if [[ "$supported" == *" $t "* ]]; then
            continue
        elif [[ "$preview" == *" $t "* ]]; then
            print_warning "$t is a preview target in $version"
        else
            print_warning "$t is not a target of $version (supported:${supported% })"
        fi
    done
}

# Function to install ESP-IDF versions
install_idf_versions() {
    local versions=("$@")
    local from_config=false

    if [[ ${#versions[@]} -eq 0 ]]; then
        print_status "Installing ESP-IDF versions from configuration..."
        source "$SCRIPT_DIR/config_loader.sh"
        if ! load_config; then
            print_error "Failed to load configuration"
            return 1
        fi
        local required_versions
        required_versions=$(get_idf_versions)
        if [[ -z "$required_versions" ]]; then
            print_error "No ESP-IDF versions specified in configuration"
            return 1
        fi
        read -ra versions <<< "$required_versions"
        from_config=true
    elif [[ -n "${PROJECT_PATH:-}" ]] || [[ -f "$SCRIPT_DIR/../app_config.yml" ]]; then
        # Explicit versions: still read the project's target, when there is a project.
        source "$SCRIPT_DIR/config_loader.sh"
        load_config >/dev/null 2>&1 || true
    fi

    local targets
    targets=$(resolve_targets)
    print_status "ESP-IDF versions: ${versions[*]} (tools for: $targets)"

    local version idf_dir
    for version in "${versions[@]}"; do
        check_version_and_targets "$version" "$targets"
        idf_dir=$(esp_idf_dir_for_version "$version")

        if [[ -d "$idf_dir" ]] && [[ "$FORCE" != "true" ]]; then
            print_warning "ESP-IDF $version already exists at $idf_dir"
            print_status "Use --force to reinstall, or update to move it on"
            continue
        fi

        # Remove existing directory if forcing
        if [[ -d "$idf_dir" ]] && [[ "$FORCE" == "true" ]]; then
            print_status "Removing existing ESP-IDF $version..."
            rm -rf "$idf_dir"
        fi

        idf_clone_and_install "$version" "$targets" "$SHALLOW" || return 1
    done

    # The default: the first version of app_config.yml; for explicit versions only when there is no default yet.
    local default_link
    default_link="$(esp_idf_root)/esp-idf"
    if [[ "$from_config" == "true" ]] || [[ ! -e "$default_link" ]]; then
        switch_default_version "${versions[0]}"
    fi

    print_success "ESP-IDF installation complete"
}

# The versions of idf_versions.yml, each marked when installed.
show_available_versions() {
    local table line version
    if ! table=$(idf_versions_cmd list --format table); then
        print_error "Could not read idf_versions.yml (python3 needed)"
        return 1
    fi
    while IFS= read -r line; do
        version="${line%% *}"
        if [[ "$version" == "VERSION" ]]; then
            echo "  $line"
        elif find_esp_idf_dir "$version" >/dev/null; then
            echo "* $line"
        else
            echo "  $line"
        fi
    done <<< "$table"
    echo ""
    echo "* installed under $(esp_idf_root). CI: pr = every run, full = tags, schedules and manual runs."
}

# Function to list installed versions
list_installed_versions() {
    print_status "Listing installed ESP-IDF versions..."
    list_esp_idf_versions
}

# Function to export ESP-IDF environment
export_idf_environment() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_error "ESP-IDF version not specified"
        print_status "Usage: ./manage_idf.sh export <version>"
        return 1
    fi

    if export_esp_idf_version "$version"; then
        print_success "ESP-IDF environment exported for version $version"
        print_status "Environment variables set:"
        print_status "  IDF_PATH: $IDF_PATH"
        print_status "  IDF_VERSION: $IDF_VERSION"

        # Show available commands
        if command_exists idf.py; then
            print_status "Available commands:"
            print_status "  idf.py --version"
            print_status "  idf.py --help"
        fi
    else
        print_error "Failed to export ESP-IDF environment for version $version"
        return 1
    fi
}

# Function to switch default ESP-IDF version
switch_default_version() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_error "ESP-IDF version not specified"
        print_status "Usage: ./manage_idf.sh switch <version>"
        return 1
    fi

    local idf_dir
    if ! idf_dir=$(find_esp_idf_dir "$version"); then
        print_error "ESP-IDF version $version not found at $idf_dir"
        return 1
    fi
    local default_link
    default_link="$(esp_idf_root)/esp-idf"

    # Remove existing symlink
    if [[ -L "$default_link" ]]; then
        rm "$default_link"
    fi

    # Create new symlink
    ln -sf "$idf_dir" "$default_link"

    print_success "Default ESP-IDF version switched to $version"
    print_status "Symlink created: $default_link -> $idf_dir"
}

# Function to update specific ESP-IDF version
update_idf_version() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_error "ESP-IDF version not specified"
        print_status "Usage: ./manage_idf.sh update <version>"
        return 1
    fi

    local idf_dir
    if ! idf_dir=$(find_esp_idf_dir "$version"); then
        print_error "ESP-IDF version $version not found at $idf_dir"
        return 1
    fi

    print_status "Updating ESP-IDF $version..."
    idf_clone_and_install "$version" "$(resolve_targets)" "$SHALLOW"
}

# Check an installed version: the folder, the version in its sources, export.sh, and idf.py after export.
verify_idf_version() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_error "ESP-IDF version not specified"
        print_status "Usage: ./manage_idf.sh verify <version>"
        return 1
    fi

    local idf_dir failed=0 have want
    if ! idf_dir=$(find_esp_idf_dir "$version"); then
        print_error "ESP-IDF version $version not found at $idf_dir"
        return 1
    fi
    print_status "Verifying ESP-IDF $version in $idf_dir"

    want=$(idf_major_minor "$version")
    if have=$(idf_dir_major_minor "$idf_dir"); then
        if [[ -z "$want" ]] || [[ "$have" == "$want" ]]; then
            print_success "sources are ESP-IDF $have"
        else
            print_error "sources are ESP-IDF $have, not $want"
            failed=1
        fi
    else
        print_error "no tools/cmake/version.cmake: not an ESP-IDF checkout"
        failed=1
    fi

    if [[ -d "$idf_dir/.git" ]] || [[ -f "$idf_dir/.git" ]]; then
        print_success "git: $(git -C "$idf_dir" describe --tags --always 2>/dev/null || echo unknown)"
    fi

    if [[ ! -f "$idf_dir/export.sh" ]]; then
        print_error "no export.sh"
        failed=1
    else
        # In a child shell, so this shell keeps its environment.
        local reported
        if reported=$(bash -c '. "$1/export.sh" >/dev/null 2>&1 && idf.py --version' _ "$idf_dir" 2>/dev/null); then
            print_success "idf.py after export.sh: $reported"
            if [[ -n "$want" ]] && [[ "$reported" != *"v$want"* ]]; then
                print_error "idf.py reports $reported, not v$want"
                failed=1
            fi
        else
            print_error "export.sh failed or idf.py did not run: run install.sh in $idf_dir (or manage_idf.sh update)"
            failed=1
        fi
    fi

    if [[ $failed -ne 0 ]]; then
        print_error "ESP-IDF $version: verification failed"
        return 1
    fi
    print_success "ESP-IDF $version: OK"
}

# Function to clean specific ESP-IDF version
clean_idf_version() {
    local version="$1"

    if [[ -z "$version" ]]; then
        print_error "ESP-IDF version not specified"
        print_status "Usage: ./manage_idf.sh uninstall <version>"
        return 1
    fi

    local esp_dir
    esp_dir=$(esp_idf_root)
    local idf_dir
    if ! idf_dir=$(find_esp_idf_dir "$version"); then
        print_error "ESP-IDF version $version not found at $idf_dir"
        return 1
    fi
    local default_link="$esp_dir/esp-idf"

    # Check if this is the default version
    if [[ -L "$default_link" ]] && same_dir "$default_link" "$idf_dir"; then
        print_warning "Cannot remove default ESP-IDF version"
        print_status "Switch to another version first: ./manage_idf.sh switch <other_version>"
        return 1
    fi

    local mm
    mm=$(idf_dir_major_minor "$idf_dir" 2>/dev/null || true)

    print_status "Removing ESP-IDF $version..."
    rm -rf "$idf_dir"
    print_success "ESP-IDF $version removed successfully"

    if [[ "$PYTHON_ENV" == "true" ]]; then
        remove_python_env "$mm"
    fi
}

# Remove the Python environments of one ESP-IDF major.minor (idf<mm>_py<x.y>_env), unless another installed
# version of the same major.minor still uses them. Toolchains are shared between versions and stay.
remove_python_env() {
    local mm="$1" dir other envs_dir
    if [[ -z "$mm" ]]; then
        print_warning "Unknown ESP-IDF version: Python environment left in place"
        return 0
    fi
    for other in "$(esp_idf_root)"/esp-idf-*; do
        [[ -d "$other" ]] || continue
        if [[ "$(idf_dir_major_minor "$other" 2>/dev/null || true)" == "$mm" ]]; then
            print_warning "$other is also ESP-IDF $mm: its Python environment stays"
            return 0
        fi
    done
    envs_dir="${IDF_TOOLS_PATH:-$HOME/.espressif}/python_env"
    local removed=0
    for dir in "$envs_dir"/idf"$mm"_py*_env; do
        [[ -d "$dir" ]] || continue
        rm -rf "$dir"
        print_success "Removed $dir"
        removed=$((removed + 1))
    done
    if [[ $removed -eq 0 ]]; then
        print_status "No Python environment for ESP-IDF $mm in $envs_dir"
    fi
}

# Function to show current status
show_status() {
    print_status "ESP-IDF Status Report"
    echo ""

    # Show current environment
    if [[ -n "${IDF_PATH:-}" ]]; then
        print_success "Current ESP-IDF environment:"
        print_status "  IDF_PATH: $IDF_PATH"
        print_status "  IDF_VERSION: ${IDF_VERSION:-}"
    else
        print_warning "No ESP-IDF environment currently exported"
    fi
    print_status "  Tools: ${IDF_TOOLS_PATH:-$HOME/.espressif}"

    echo ""

    # Show default symlink
    local default_link
    default_link="$(esp_idf_root)/esp-idf"

    if [[ -L "$default_link" ]]; then
        local target
        target=$(readlink "$default_link")
        print_success "Default ESP-IDF version: $(idf_version_for_dir "$target")"
        print_status "  Symlink: $default_link -> $target"
    else
        print_warning "No default ESP-IDF symlink found"
    fi

    echo ""

    # List all installed versions
    list_esp_idf_versions
}

# Main function
main() {
    local command="${1:-}"

    # Check if command is provided: usage on stderr, exit status 2 (usage error)
    if [[ -z "$command" ]]; then
        print_error "No command specified" >&2
        show_help >&2
        exit 2
    fi
    shift

    # Execute command
    case "$command" in
        "install")
            install_idf_versions "$@"
            ;;
        "available")
            show_available_versions
            ;;
        "list")
            list_installed_versions
            ;;
        "export")
            export_idf_environment "${1:-}"
            ;;
        "switch")
            switch_default_version "${1:-}"
            ;;
        "update")
            update_idf_version "${1:-}"
            ;;
        "verify")
            verify_idf_version "${1:-}"
            ;;
        "uninstall"|"clean")
            clean_idf_version "${1:-}"
            ;;
        "status")
            show_status
            ;;
        *)
            print_error "Unknown command: $command" >&2
            show_help >&2
            exit 2
            ;;
    esac
}

# Run main function with all arguments
main "$@"
