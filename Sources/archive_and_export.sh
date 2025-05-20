#!/bin/bash

###
# This script archives an Xcode project and exports it.

set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --auth-key-path PATH                Path to App Store Connect API key (required)"
    echo "  --auth-key-id ID                    App Store Connect API Key ID (required)"
    echo "  --auth-key-issuer-id ID             App Store Connect API Issuer ID (required)"
    echo "  -b, --build-path PATH               Build products path (default: .build)"
    echo "  -c, --config CONFIG                 Build configuration (default: Release)"
    echo "  -e, --export-options-plist PATH     Path to export options plist (required)"
    echo "  -h, --help                          Show this help message"
    echo "  -p, --project PROJECT               Xcode project path (required)"
    echo "  --platform PLATFORM                 Platform (default: iOS, options: iOS, macOS,"
    echo "                                      tvOS, visionOS)"
    echo "  -s, --scheme SCHEME                 Scheme name (required)"
    echo ""
    echo "Environment variables:"
    echo "  APP_STORE_CONNECT_API_ISSUER_ID     App Store Connect API Issuer"
    echo "  APP_STORE_CONNECT_API_KEY_ID        App Store Connect API Key"
    echo "  APP_STORE_CONNECT_API_KEY_PATH      Path to App Store Connect API key"
    echo "  OTHER_ARCHIVE_FLAGS                 Additional flags to pass to the archive command"
    echo "  OTHER_EXPORT_FLAGS                  Additional flags to pass to the export command"
    echo "  XCODE_BUILD_PATH                    Build products path"
    echo "  XCODE_CONFIG                        Build configuration"
    echo "  XCODE_EXPORT_OPTIONS_PLIST          Path to export options plist"
    echo "  XCODE_PLATFORM                      Platform"
    echo "  XCODE_PROJECT                       Xcode project path"
    echo "  XCODE_SCHEME                        Scheme name"
    exit 1
}

# Gets destination from platform
get_destination() {
    local platform="$1"
    echo "generic/platform=$platform"
}

# Parses arguments and validates parameters.
parse_args() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auth-key-path)
                AUTH_KEY_PATH="$2"
                shift 2
                ;;
            --auth-key-id)
                AUTH_KEY_ID="$2"
                shift 2
                ;;
            --auth-key-issuer-id)
                AUTH_KEY_ISSUER="$2"
                shift 2
                ;;
            -b|--build-path)
                BUILD_PATH="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG="$2"
                shift 2
                ;;
            -e|--export-options-plist)
                EXPORT_OPTIONS_PLIST="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -p|--project)
                PROJECT="$2"
                shift 2
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            -s|--scheme)
                SCHEME="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Set values from environment variables if not set by command line
    CONFIG="${CONFIG:-$XCODE_CONFIG}"
    BUILD_PATH="${BUILD_PATH:-$XCODE_BUILD_PATH}"
    EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$XCODE_EXPORT_OPTIONS_PLIST}"
    PLATFORM="${PLATFORM:-$XCODE_PLATFORM}"
    PROJECT="${PROJECT:-$XCODE_PROJECT}"
    SCHEME="${SCHEME:-$XCODE_SCHEME}"
    AUTH_KEY_ID="${AUTH_KEY_ID:-$APP_STORE_CONNECT_API_KEY_ID}"
    AUTH_KEY_ISSUER="${AUTH_KEY_ISSUER:-$APP_STORE_CONNECT_API_ISSUER_ID}"
    AUTH_KEY_PATH="${AUTH_KEY_PATH:-$APP_STORE_CONNECT_API_KEY_PATH}"

    # If config is still empty, set it to the default value
    if [ -z "$CONFIG" ]; then
        CONFIG="Release"
    fi

    # If build path is still empty, set it to the default value
    if [ -z "$BUILD_PATH" ]; then
        BUILD_PATH=".build"
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

    # Create directories if they don’t exist
    local derived_data_path="$BUILD_PATH/DerivedData"
    local package_cache_path="$BUILD_PATH/SwiftPM"
    mkdir -p "$BUILD_PATH" "$derived_data_path" "$package_cache_path"
    package_cache_path=$(realpath "$package_cache_path")

    # Command construction
    local xcode_cmd="xcodebuild archive -project '$PROJECT' -scheme '$SCHEME'"
    xcode_cmd="$xcode_cmd -destination '$DESTINATION'"
    xcode_cmd="$xcode_cmd -derivedDataPath '$derived_data_path'"
    xcode_cmd="$xcode_cmd -packageCachePath '$package_cache_path'"
    xcode_cmd="$xcode_cmd -archivePath '$archive_path' -configuration '$CONFIG'"
    xcode_cmd="$xcode_cmd -authenticationKeyPath '$AUTH_KEY_PATH'"
    xcode_cmd="$xcode_cmd -authenticationKeyID '$AUTH_KEY_ID'"
    xcode_cmd="$xcode_cmd -authenticationKeyIssuerID '$AUTH_KEY_ISSUER'"
    xcode_cmd="$xcode_cmd $OTHER_ARCHIVE_FLAGS"

    # Execute command
    echo "Executing archive command:"
    echo "$xcode_cmd"

    # Remove existing archive if it exists
    rm -r "$archive_path" 2>/dev/null || true

    # Construct pipe chain
    local pipe_cmd="$xcode_cmd 2>&1 | tee '$log_file'"

    # Add xcbeautify to pipe chain if available
    if command -v xcbeautify >/dev/null 2>&1; then
        pipe_cmd="$pipe_cmd | xcbeautify"
    fi

    # Execute pipe chain
    eval "$pipe_cmd"
    local archive_status=$?
    return $archive_status
}

# Export the archive.
export_app() {
    local archive_path="$1"
    local log_file="$2"

    echo "Exporting archive..."

    local export_cmd="xcodebuild -exportArchive"
    export_cmd="$export_cmd -archivePath '$archive_path'"
    export_cmd="$export_cmd -exportOptionsPlist '$EXPORT_OPTIONS_PLIST'"
    export_cmd="$export_cmd -exportPath '$archive_path/Products'"
    export_cmd="$export_cmd -authenticationKeyPath '$AUTH_KEY_PATH'"
    export_cmd="$export_cmd -authenticationKeyID '$AUTH_KEY_ID'"
    export_cmd="$export_cmd -authenticationKeyIssuerID '$AUTH_KEY_ISSUER'"
    export_cmd="$export_cmd $OTHER_EXPORT_FLAGS"

    # Execute export command
    echo "Executing export command:"
    echo "$export_cmd"

    # Construct pipe chain
    local export_pipe_cmd="$export_cmd 2>&1 | tee -a '$log_file'"

    # Execute pipe chain
    eval "$export_pipe_cmd"
    local export_status=$?
    return $export_status
}

# Parse and validate arguments
parse_args "$@"

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
