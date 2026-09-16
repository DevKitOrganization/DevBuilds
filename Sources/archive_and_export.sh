#!/bin/bash

###
# This script archives an Xcode project and exports it.

set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --auth-key-id ID                   App Store Connect API Key ID (required)"
    echo "  --auth-key-issuer-id ID            App Store Connect API Issuer ID (required)"
    echo "  --auth-key-path PATH               Path to App Store Connect API key (required)"
    echo "  -b, --build-path PATH              Build products path (default: .build)"
    echo "  -c, --config CONFIG                Build configuration (default: Release)"
    echo "  --derived-data-path PATH           DerivedData path (default: BUILD_PATH/DerivedData)"
    echo "  -e, --export-options-plist PATH    Path to export options plist (required)"
    echo "  -h, --help                         Show this help message"
    echo "  --platform PLATFORM                Platform (default: iOS, options: iOS, macOS,"
    echo "                                     tvOS, visionOS)"
    echo "  -p, --project PROJECT              Xcode project path (required)"
    echo "  -s, --scheme SCHEME                Scheme name (required)"
    echo "  --source-packages-path PATH        Source packages checkout path (optional)"
    echo ""
    echo "Environment variables:"
    echo "  APP_STORE_CONNECT_API_ISSUER_ID    App Store Connect API Issuer"
    echo "  APP_STORE_CONNECT_API_KEY_ID       App Store Connect API Key"
    echo "  APP_STORE_CONNECT_API_KEY_PATH     Path to App Store Connect API key"
    echo "  OTHER_ARCHIVE_FLAGS                Additional flags to pass to the archive command"
    echo "  OTHER_EXPORT_FLAGS                 Additional flags to pass to the export command"
    echo "  OTHER_XCBEAUTIFY_FLAGS             Additional flags to pass to xcbeautify"
    echo "  XCODE_BUILD_PATH                   Build products path"
    echo "  XCODE_CONFIG                       Build configuration"
    echo "  XCODE_DERIVED_DATA_PATH            DerivedData path"
    echo "  XCODE_EXPORT_OPTIONS_PLIST         Path to export options plist"
    echo "  XCODE_PLATFORM                     Platform"
    echo "  XCODE_PROJECT                      Xcode project path"
    echo "  XCODE_SCHEME                       Scheme name"
    echo "  XCODE_SOURCE_PACKAGES_PATH         Source packages checkout path"
    exit 1
}

# Gets destination from platform
get_destination() {
    local platform="$1"
    echo "generic/platform=$platform"
}

# Check that a value-taking option has a nonempty value rather than another option.
# Return nonzero with a diagnostic before the caller assigns values or shifts arguments.
validate_option_value() {
    local option="$1"
    local value="$2"

    if [[ -z "$value" || "$value" == -* ]]; then
        printf 'Error: %s requires a nonempty value (not another option)\n' "$option" >&2
        return 1
    fi
}

# Parses arguments and validates parameters.
parse_args() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auth-key-id)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                AUTH_KEY_ID="$2"
                shift 2
                ;;
            --auth-key-issuer-id)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                AUTH_KEY_ISSUER="$2"
                shift 2
                ;;
            --auth-key-path)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                AUTH_KEY_PATH="$2"
                shift 2
                ;;
            -b|--build-path)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                BUILD_PATH="$2"
                shift 2
                ;;
            -c|--config)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                CONFIG="$2"
                shift 2
                ;;
            --derived-data-path)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                DERIVED_DATA_PATH="$2"
                shift 2
                ;;
            -e|--export-options-plist)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                EXPORT_OPTIONS_PLIST="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            --platform)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                PLATFORM="$2"
                shift 2
                ;;
            -p|--project)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                PROJECT="$2"
                shift 2
                ;;
            -s|--scheme)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                SCHEME="$2"
                shift 2
                ;;
            --source-packages-path)
                if ! validate_option_value "$1" "${2:-}"; then
                    exit 1
                fi
                SOURCE_PACKAGES_PATH="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Set values from environment variables if not set by command line
    AUTH_KEY_ISSUER="${AUTH_KEY_ISSUER:-$APP_STORE_CONNECT_API_ISSUER_ID}"
    AUTH_KEY_ID="${AUTH_KEY_ID:-$APP_STORE_CONNECT_API_KEY_ID}"
    AUTH_KEY_PATH="${AUTH_KEY_PATH:-$APP_STORE_CONNECT_API_KEY_PATH}"
    BUILD_PATH="${BUILD_PATH:-$XCODE_BUILD_PATH}"
    CONFIG="${CONFIG:-$XCODE_CONFIG}"
    if [[ -z "$DERIVED_DATA_PATH" ]]; then
        DERIVED_DATA_PATH="${XCODE_DERIVED_DATA_PATH:-}"
    fi
    EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$XCODE_EXPORT_OPTIONS_PLIST}"
    PLATFORM="${PLATFORM:-$XCODE_PLATFORM}"
    PROJECT="${PROJECT:-$XCODE_PROJECT}"
    SCHEME="${SCHEME:-$XCODE_SCHEME}"
    if [[ -z "$SOURCE_PACKAGES_PATH" ]]; then
        SOURCE_PACKAGES_PATH="${XCODE_SOURCE_PACKAGES_PATH:-}"
    fi

    # If config is still empty, set it to the default value
    if [ -z "$CONFIG" ]; then
        CONFIG="Release"
    fi

    # If build path is still empty, set it to the default value
    if [ -z "$BUILD_PATH" ]; then
        BUILD_PATH=".build"
    fi

    # Keep the default DerivedData directory relative to the resolved build output path.
    if [[ -z "$DERIVED_DATA_PATH" ]]; then
        DERIVED_DATA_PATH="$BUILD_PATH/DerivedData"
    fi

    # If platform is still empty, set it to the default value
    if [ -z "$PLATFORM" ]; then
        PLATFORM="iOS"
    fi

    # Get destination from platform
    DESTINATION="$(get_destination "$PLATFORM")"

    # Validate required parameters
    if [ -z "$PROJECT" ]; then
        echo "Error: Project is required"
        usage
    elif [ -z "$SCHEME" ]; then
        echo "Error: Scheme is required"
        usage
    elif [ -z "$AUTH_KEY_PATH" ]; then
        echo "Error: App Store Connect API key path is required"
        usage
    elif [ -z "$AUTH_KEY_ID" ]; then
        echo "Error: App Store Connect API Key ID is required"
        usage
    elif [ -z "$AUTH_KEY_ISSUER" ]; then
        echo "Error: App Store Connect API Issuer is required"
        usage
    elif [ -z "$EXPORT_OPTIONS_PLIST" ]; then
        echo "Error: Export options plist is required"
        usage
    fi
}

# Creates and executes archive command.
archive_app() {
    local archive_path="$1"
    local log_file="$2"

    local xcode_cmd=(
        xcodebuild archive
        -project "$PROJECT"
        -scheme "$SCHEME"
        -destination "$DESTINATION"
        -derivedDataPath "$DERIVED_DATA_PATH"
        -archivePath "$archive_path"
        -configuration "$CONFIG"
        -authenticationKeyPath "$AUTH_KEY_PATH"
        -authenticationKeyID "$AUTH_KEY_ID"
        -authenticationKeyIssuerID "$AUTH_KEY_ISSUER"
    )
    local archive_status

    # Add source packages checkout path if specified
    if [[ -n "$SOURCE_PACKAGES_PATH" ]]; then
        xcode_cmd+=(-clonedSourcePackagesDirPath "$SOURCE_PACKAGES_PATH")
    fi

    # Add caller-supplied flags last so they follow all generated arguments
    xcode_cmd+=("${ARCHIVE_ARGUMENTS[@]}")

    # Execute command
    echo "Executing archive command:"
    log_xcode_command "${xcode_cmd[@]}"

    # Remove existing archive if it exists
    rm -r "$archive_path" 2>/dev/null || true

    # Execute directly so parameter values are arguments rather than shell source.
    if command -v xcbeautify >/dev/null 2>&1; then
        NSUnbufferedIO=YES "${xcode_cmd[@]}" 2>&1 |
            tee "$log_file" |
            xcbeautify "${XCBEAUTIFY_ARGUMENTS[@]}"
    else
        NSUnbufferedIO=YES "${xcode_cmd[@]}" 2>&1 | tee "$log_file"
    fi
    archive_status=$?
    return "$archive_status"
}

# Export the archive.
export_app() {
    local archive_path="$1"
    local log_file="$2"

    echo "Exporting archive..."

    local xcode_cmd=(
        xcodebuild -exportArchive
        -archivePath "$archive_path"
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
        -exportPath "$archive_path/Products"
        -authenticationKeyPath "$AUTH_KEY_PATH"
        -authenticationKeyID "$AUTH_KEY_ID"
        -authenticationKeyIssuerID "$AUTH_KEY_ISSUER"
    )
    local export_status

    # Add caller-supplied flags last so they follow all generated arguments
    xcode_cmd+=("${EXPORT_ARGUMENTS[@]}")

    # Execute export command
    echo "Executing export command:"
    log_xcode_command "${xcode_cmd[@]}"

    NSUnbufferedIO=YES "${xcode_cmd[@]}" 2>&1 | tee "$log_file"
    export_status=$?
    return "$export_status"
}

# Print the Xcode invocation with Bash escaping to preserve visible argument boundaries.
# This is a display operation; the command is executed separately using its argument array.
log_xcode_command() {
    printf 'NSUnbufferedIO=YES'
    printf ' %q' "$@"
    printf '\n'
}

# Parse extra arguments into PARSED_EXTRA_FLAGS, replacing its previous contents on success.
# A private file preserves the parser's failure status; process substitution would hide it.
# NUL delimiters preserve empty arguments and whitespace without interpreting shell syntax.
parse_extra_flags() {
    local extra_flags="$1"
    local script_directory
    local flags_file
    local argument

    if ! script_directory="$(dirname "$0")"; then
        return 1
    fi
    if ! flags_file="$(mktemp "${TMPDIR:-/tmp}/devbuilds-flags.XXXXXX")"; then
        return 1
    fi
    if ! "$script_directory/split_shell_words.py" "$extra_flags" > "$flags_file"; then
        rm -f "$flags_file"
        return 1
    fi

    PARSED_EXTRA_FLAGS=()
    while IFS= read -r -d '' argument; do
        PARSED_EXTRA_FLAGS+=("$argument")
    done < "$flags_file"

    if ! rm -f "$flags_file"; then
        return 1
    fi
}

# Parse and validate arguments
parse_args "$@"

# Parse extra flags before creating build output or starting either Xcode phase.
if ! parse_extra_flags "${OTHER_ARCHIVE_FLAGS:-}"; then
    exit 1
fi
ARCHIVE_ARGUMENTS=("${PARSED_EXTRA_FLAGS[@]}")
if ! parse_extra_flags "${OTHER_EXPORT_FLAGS:-}"; then
    exit 1
fi
EXPORT_ARGUMENTS=("${PARSED_EXTRA_FLAGS[@]}")
if ! parse_extra_flags "${OTHER_XCBEAUTIFY_FLAGS:-}"; then
    exit 1
fi
XCBEAUTIFY_ARGUMENTS=("${PARSED_EXTRA_FLAGS[@]}")

mkdir -p "$BUILD_PATH"

# Create paths
ARCHIVE_PATH="${BUILD_PATH}/${SCHEME}.xcarchive"
ARCHIVE_LOG="${BUILD_PATH}/${SCHEME}_archive.log"
EXPORT_LOG="${BUILD_PATH}/${SCHEME}_export.log"

# Archive the app
archive_app "$ARCHIVE_PATH" "$ARCHIVE_LOG"
ARCHIVE_STATUS=$?

# If archive succeeded, export the archive
if [ $ARCHIVE_STATUS -eq 0 ]; then
    echo "Archive completed successfully"

    # Export the archive
    export_app "$ARCHIVE_PATH" "$EXPORT_LOG"
    EXPORT_STATUS=$?

    if [ $EXPORT_STATUS -eq 0 ]; then
        echo "Export completed successfully"
    else
        echo "Export failed"
        exit $EXPORT_STATUS
    fi
else
    echo "Archive failed"
    exit $ARCHIVE_STATUS
fi

echo "Archive log: ${ARCHIVE_LOG}"
echo "Export log: ${EXPORT_LOG}"
exit 0
