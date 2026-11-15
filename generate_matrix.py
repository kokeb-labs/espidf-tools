#!/usr/bin/env python3
"""
Generate CI matrix from centralized configuration.
This script reads app_config.yml and outputs GitHub Actions matrix configuration.
Supports hierarchical configuration where apps can override global settings.
"""

import sys
import yaml
import json
import argparse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import idf_versions as idfv  # noqa: E402 - next to this script

def show_help():
    """Show comprehensive help information."""
    print("ESP32 CI Matrix Generator")
    print("")
    print("Usage: python3 generate_matrix.py [OPTIONS]")
    print("")
    print("OPTIONS:")
    print("  --help, -h                  - Show this help message")
    print("  --output <file>             - Output to file instead of stdout")
    print("  --format <format>           - Output format: json, yaml (default: json)")
    print("  --filter <app>              - Filter output for specific app only")
    print("  --verbose                   - Show detailed processing information")
    print("  --validate                  - Validate configuration before generating matrix")
    print("  --project-path <path>       - Path to project directory containing app_config.yml")
    print("  --ci-scope <scope>          - pr: per app only the ci: pr version of idf_versions.yml (else its")
    print("                                first); full/all: every version (default all); auto: pr on pull")
    print("                                requests and branch pushes, full on tags, schedules, manual runs")
    print("")
    print("PURPOSE:")
    print("  Generate CI matrix from centralized configuration for GitHub Actions")
    print("")
    print("WHAT IT DOES:")
    print("  • Reads app_config.yml configuration file")
    print("  • Generates GitHub Actions matrix configuration")
    print("  • Supports hierarchical configuration overrides")
    print("  • Handles per-app ESP-IDF version and build type requirements")
    print("  • Applies CI exclusions and filters")
    print("  • Outputs in JSON or YAML format")
    print("")
    print("CONFIGURATION SOURCES:")
    print("  • Global defaults from metadata section")
    print("  • Per-app overrides for ESP-IDF versions")
    print("  • Per-app overrides for build types")
    print("  • CI-specific exclusions and filters")
    print("  • App-specific CI enable/disable flags")
    print("")
    print("EXAMPLES:")
    print("  # Basic usage (output to stdout)")
    print("  python3 generate_matrix.py")
    print("")
    print("  # Output to file")
    print("  python3 generate_matrix.py --output matrix.json")
    print("")
    print("  # YAML format output")
    print("  python3 generate_matrix.py --format yaml")
    print("")
    print("  # Filter for specific app")
    print("  python3 generate_matrix.py --filter gpio_test")
    print("")
    print("  # Validate configuration")
    print("  python3 generate_matrix.py --validate")
    print("")
    print("  # Verbose output with validation")
    print("  python3 generate_matrix.py --verbose --validate --output matrix.json")
    print("")
    print("OUTPUT FORMAT:")
    print("  • JSON: Standard GitHub Actions matrix format")
    print("  • YAML: Alternative format for other CI systems")
    print("  • Structure: idf_version, idf_ref, idf_status, build_type, app_name, target, config_source")
    print("")
    print("CONFIGURATION FILE:")
    print("  • Location: examples/esp32/app_config.yml")
    print("  • Format: YAML with hierarchical structure")
    print("  • Required sections: metadata, apps")
    print("  • Optional sections: ci_config")
    print("")
    print("MATRIX GENERATION LOGIC:")
    print("  1. Load global defaults from metadata")
    print("  2. Apply per-app overrides for ESP-IDF versions")
    print("  3. Apply per-app overrides for build types")
    print("  4. Filter by CI enable/disable flags")
    print("  5. Apply CI exclusions")
    print("  6. Generate final matrix entries")
    print("")
    print("CI INTEGRATION:")
    print("  • GitHub Actions: Use JSON output directly in matrix strategy")
    print("  • GitLab CI: Convert JSON to YAML format")
    print("  • Jenkins: Parse JSON output for pipeline configuration")
    print("  • Local testing: Validate configuration before CI deployment")
    print("")
    print("TROUBLESHOOTING:")
    print("  • Configuration not found: Check file paths and working directory")
    print("  • Invalid YAML: Validate syntax with yamllint")
    print("  • Matrix empty: Check CI enable flags and exclusions")
    print("  • Build type mismatch: Verify per-app build type configurations")
    print("")
    print("For detailed information, see: docs/README_CI_CACHING_STRATEGY.md")
    sys.exit(0)

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Generate CI matrix from ESP32 app configuration",
        add_help=False  # We'll handle help manually
    )
    
    parser.add_argument("--help", "-h", action="store_true", help="Show help message")
    parser.add_argument("--output", "-o", help="Output file path")
    parser.add_argument("--format", "-f", choices=["json", "yaml"], default="json", help="Output format")
    parser.add_argument("--filter", help="Filter output for specific app")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    parser.add_argument("--validate", action="store_true", help="Validate configuration")
    parser.add_argument("--project-path", "-p", help="Path to project directory containing app_config.yml")
    parser.add_argument("--ci-scope", choices=["pr", "full", "all", "auto"], default="all",
                        help="Versions per app: pr (the ci: pr one of idf_versions.yml), full/all (every one), "
                             "auto (from GITHUB_EVENT_NAME and GITHUB_REF)")
    
    args = parser.parse_args()
    
    if args.help:
        show_help()
    
    return args

def load_config(project_path=None):
    """Load the apps configuration file."""
    if project_path:
        # Use provided project path
        project_dir = Path(project_path).resolve()
        config_file = project_dir / "app_config.yml"
        
        if not config_file.exists():
            print(f"Error: Configuration file not found: {config_file}", file=sys.stderr)
            print(f"Please check the project path: {project_path}", file=sys.stderr)
            sys.exit(1)
    else:
        # Try multiple possible paths for the configuration file
        possible_paths = [
            # When run from workspace root
            Path("examples/esp32/app_config.yml"),
            # When run from examples/esp32 directory
            Path("app_config.yml"),
            # When run from examples/esp32/scripts directory
            Path("../app_config.yml"),
            # When run from .github/workflows directory  
            Path("../../examples/esp32/app_config.yml"),
            # Absolute path calculation from script location
            Path(__file__).resolve().parent.parent / "app_config.yml"
        ]
        
        config_file = None
        for path in possible_paths:
            if path.exists():
                config_file = path
                break
    
    if not config_file:
        print(f"Error: Configuration file not found in any of these locations:", file=sys.stderr)
        for path in possible_paths:
            print(f"  {path.resolve()}", file=sys.stderr)
        sys.exit(1)
    
    try:
        with open(config_file, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        print(f"Error loading configuration: {e}", file=sys.stderr)
        sys.exit(1)

def load_known_versions():
    """The entries of idf_versions.yml; an empty list (with a warning) when it cannot be read."""
    try:
        return idfv.load()
    except idfv.VersionsError as exc:
        print(f"Warning: {exc}; ESP-IDF versions are not checked", file=sys.stderr)
        return []


def expand_versions(versions):
    """(version, position) pairs; the position picks the nested build_types list."""
    return [(v, i) for i, v in enumerate(versions)]


def select_for_scope(pairs, known, scope):
    """pr: the app's versions with ci: pr, else its first; full and all: every one."""
    if scope in ("full", "all") or not pairs:
        return pairs
    picked = [(v, i) for v, i in pairs
              if (idfv.find(known, v) or {}).get("ci") == "pr"]
    return picked or pairs[:1]


def generate_matrix(project_path=None, ci_scope="all"):
    """Generate CI matrix from configuration with hierarchical overrides."""
    config = load_config(project_path)
    known = load_known_versions()
    if ci_scope == "auto":
        import os  # noqa: PLC0415
        ci_scope = idfv.scope_for_event(os.environ.get("GITHUB_EVENT_NAME", ""),
                                                os.environ.get("GITHUB_REF", ""))
    warned = set()

    def warn_once(message):
        if message not in warned:
            warned.add(message)
            print(f"Warning: {message}", file=sys.stderr)

    # Global defaults from metadata
    global_idf_versions = config['metadata'].get('idf_versions', [idfv.default_version(known)
                                                                  or 'release/v5.5'])
    global_build_types_per_idf = config['metadata'].get('build_types', [['Debug', 'Release']])
    
    # Create a mapping from IDF version to its allowed build types
    idf_to_build_types = {}
    for idf_version, i in expand_versions(global_idf_versions):
        if i < len(global_build_types_per_idf):
            idf_to_build_types[idf_version] = global_build_types_per_idf[i]
        else:
            # Fallback if no build types specified for this IDF version
            idf_to_build_types[idf_version] = ['Debug', 'Release']
    
    # Optional excludes for special cases - handle None case
    exclude_combinations = config.get('ci_config', {}).get('exclude_combinations', []) or []

    def is_excluded(entry: dict) -> bool:
        for exc in exclude_combinations:
            # If all keys in exc match the entry, then exclude
            if all(k in entry and entry[k] == v for k, v in exc.items()):
                return True
        return False

    # Build an explicit include list honoring per-app overrides
    include: list[dict] = []
    for app_name, app_config in config['apps'].items():
        if not app_config.get('ci_enabled', True):
            continue
        
        # Per-app overrides (app-specific settings take precedence)
        per_app_idf_versions = app_config.get('idf_versions', global_idf_versions)
        pairs = select_for_scope(expand_versions(per_app_idf_versions), known, ci_scope)
        
        # For each IDF version, determine the allowed build types
        effective_combinations = []
        for idf_version, i in pairs:
            if 'build_types' in app_config:
                # App has specific build type requirements
                app_build_types = app_config['build_types']
                
                # Check if build_types is nested (array of arrays) or flat (single array)
                if isinstance(app_build_types[0], list):
                    # Nested format: build_types: [["Debug", "Release"], ["Debug"]]
                    if i < len(app_build_types):
                        # Use the build types for this specific IDF version index
                        for build_type in app_build_types[i]:
                            effective_combinations.append((idf_version, build_type))
                    else:
                        # Fallback if no build types specified for this IDF version index
                        for build_type in ['Debug', 'Release']:
                            effective_combinations.append((idf_version, build_type))
                else:
                    # Flat format: build_types: ["Debug", "Release"] (same for all IDF versions)
                    for build_type in app_build_types:
                        effective_combinations.append((idf_version, build_type))
            else:
                # Use global IDF-specific build types
                allowed_build_types = idf_to_build_types.get(idf_version, ['Debug', 'Release'])
                for build_type in allowed_build_types:
                    effective_combinations.append((idf_version, build_type))
        
        # Generate matrix entries for this app
        target = config['metadata'].get('target', 'esp32c6')
        for idf_version, build_type in effective_combinations:
            entry = idfv.find(known, idf_version) if known else None
            if known and entry is None:
                warn_once(f"{idf_version} is not in idf_versions.yml: built as a git ref, target unchecked")
            elif entry is not None:
                if entry.get("status") == "eol":
                    warn_once(f"{idf_version} is end of life")
                if target not in (entry["targets"] or []) + (entry["preview"] or []):
                    warn_once(f"{target} is not a target of {idf_version}: {app_name} skipped for it")
                    continue
            # Create Docker-safe version for artifact naming (replace / with -)
            docker_safe_version = idf_version.replace('/', '-')
            # Create file-safe version for build directories (replace / and . with _)
            file_safe_version = idf_version.replace('/', '_').replace('.', '_')
            candidate = {
                'idf_version': idf_version,  # As in app_config.yml: build folders, build_app.sh
                'idf_ref': idfv.ref_for(known, idf_version),  # Git ref to clone
                'idf_status': entry['status'] if entry else 'unknown',  # Support period
                'idf_version_docker': docker_safe_version,  # Docker-safe format for artifacts
                'idf_version_file': file_safe_version,  # File-safe format for build directories
                'build_type': build_type,
                'app_name': app_name,  # Use app_name for consistency
                'target': target,  # Target from config
                'config_source': 'app' if ('build_types' in app_config or 'idf_versions' in app_config) else 'global'
            }
            if not is_excluded(candidate):
                include.append(candidate)

    return { 'include': include }

def validate_config(config):
    """Validate configuration structure and content."""
    errors = []
    warnings = []
    
    # Check required sections
    if 'metadata' not in config:
        errors.append("Missing required 'metadata' section")
    if 'apps' not in config:
        errors.append("Missing required 'apps' section")
    
    if errors:
        return False, errors, warnings
    
    # Validate metadata section
    metadata = config['metadata']
    if 'idf_versions' not in metadata:
        warnings.append("No 'idf_versions' specified in metadata, using default")
    if 'build_types' not in metadata:
        warnings.append("No 'build_types' specified in metadata, using default")
    if 'target' not in metadata:
        warnings.append("No 'target' specified in metadata, using default")
    
    # Validate apps section
    if not config['apps']:
        errors.append("No apps defined in configuration")
    else:
        for app_name, app_config in config['apps'].items():
            # Check if app has required fields
            if 'description' not in app_config:
                warnings.append(f"App '{app_name}' missing description")
            if 'source_file' not in app_config:
                warnings.append(f"App '{app_name}' missing source_file")
            
            # Validate build_types if specified
            if 'build_types' in app_config:
                build_types = app_config['build_types']
                if isinstance(build_types, list):
                    if build_types and isinstance(build_types[0], list):
                        # Nested format
                        for i, bt_list in enumerate(build_types):
                            if not isinstance(bt_list, list):
                                errors.append(f"App '{app_name}' build_types[{i}] is not a list")
                            elif not all(isinstance(bt, str) for bt in bt_list):
                                errors.append(f"App '{app_name}' build_types[{i}] contains non-string values")
                    else:
                        # Flat format
                        if not all(isinstance(bt, str) for bt in build_types):
                            errors.append(f"App '{app_name}' build_types contains non-string values")
                else:
                    errors.append(f"App '{app_name}' build_types is not a list")
            
            # Validate idf_versions if specified
            if 'idf_versions' in app_config:
                idf_versions = app_config['idf_versions']
                if not isinstance(idf_versions, list):
                    errors.append(f"App '{app_name}' idf_versions is not a list")
                elif not all(isinstance(v, str) for v in idf_versions):
                    errors.append(f"App '{app_name}' idf_versions contains non-string values")
    
    # ESP-IDF versions idf_versions.yml does not know (a tag or master is allowed, but unchecked)
    known = load_known_versions()
    if known:
        listed = list(metadata.get('idf_versions') or [])
        for app_config in config['apps'].values():
            listed += list(app_config.get('idf_versions') or [])
        for v in sorted(set(listed)):
            if idfv.find(known, v) is None:
                warnings.append(f"ESP-IDF version '{v}' is not in idf_versions.yml")

    # Validate ci_config if present
    if 'ci_config' in config:
        ci_config = config['ci_config']
        if 'exclude_combinations' in ci_config:
            excludes = ci_config['exclude_combinations']
            if excludes and not isinstance(excludes, list):
                errors.append("ci_config.exclude_combinations is not a list")
    
    return len(errors) == 0, errors, warnings

def main():
    """Main function."""
    args = parse_arguments()

    # Load configuration
    config = load_config(args.project_path)
    
    if args.verbose:
        print("Loading configuration...")
        print(f"Config file: {Path(__file__).resolve().parent.parent / 'app_config.yml'}")
        print(f"Apps found: {len(config['apps'])}")
        print(f"Target: {config['metadata'].get('target', 'esp32c6')}")
        print(f"IDF versions: {config['metadata'].get('idf_versions', ['release/v5.5'])}")
        print()
    
    # Validate configuration if requested
    if args.validate:
        is_valid, errors, warnings = validate_config(config)
        
        if args.verbose:
            if warnings:
                print("Configuration warnings:")
                for warning in warnings:
                    print(f"  {warning}")
            print()
        
        if not is_valid:
            print("Configuration validation failed:")
            for error in errors:
                print(f"  {error}")
            sys.exit(1)
        else:
            print("Configuration validation passed")
            if warnings:
                print(f"  {len(warnings)} warnings found")
            print()

    # Generate full matrix in compact format for GitHub Actions
    if args.verbose:
        print("Generating CI matrix...")
    
    matrix_config = generate_matrix(args.project_path, args.ci_scope)
    
    if args.verbose:
        print(f"Matrix entries: {len(matrix_config['include'])}")
        print()

    # Handle output formatting and filtering
    if args.filter:
        filtered_matrix = [
            entry for entry in matrix_config['include']
            if entry['app_name'] == args.filter
        ]
        matrix_config['include'] = filtered_matrix
        if args.verbose:
            print(f"Filtered matrix for app: {args.filter} ({len(filtered_matrix)} entries)")
    
    # Handle output to file
    if args.output:
        with open(args.output, 'w') as f:
            if args.format == 'json':
                f.write(json.dumps(matrix_config, indent=2))
            elif args.format == 'yaml':
                f.write(yaml.dump(matrix_config, indent=2))
            print(f"Matrix written to {args.output}")
        return
    
    # Always output the matrix (either filtered or full)
    if args.format == 'json':
        print(json.dumps(matrix_config))
    elif args.format == 'yaml':
        print(yaml.dump(matrix_config, indent=2))

if __name__ == '__main__':
    main()

