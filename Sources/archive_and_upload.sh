#!/bin/bash

###
# This script archives an Xcode project and uploads it to TestFlight.

set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --auth-key-path PATH                Path to App Store Connect API key (required)"
    echo "  --auth-key-id ID                    App Store Connect API Key ID (required)"
    echo "  --auth-key-issuer-id ID             App Store Connect API Issuer ID (required)"
    echo "  -b, --build-path PATH               Derived data path (default: .build)"
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
    echo "  OTHER_ARCHIVE_ARGS                  Additional args to pass to the archive command"
    echo "  OTHER_EXPORT_ARGS                   Additional args to pass to the export command" 
    echo "  XCODE_CONFIG                        Build configuration"
    echo "  XCODE_DERIVED_DATA                  Derived data path"
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

# Gets altool type from platform
get_altool_type() {
    local platform="$1"
    case "$platform" in
        iOS)
            echo "ios"
            ;;
        macOS)
            echo "macos"
            ;;
        tvOS)
            echo "appletvos"
            ;;
        visionOS)
            echo "visionos"
            ;;
        *)
            echo "Error: Unsupported platform: $platform. Supported platforms: iOS, macOS, tvOS, visionOS"
            exit 1
            ;;
    esac
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
                DERIVED_DATA="$2"
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
    DERIVED_DATA="${DERIVED_DATA:-$XCODE_DERIVED_DATA}"
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

    # If derived data path is still empty, set it to the default value
    if [ -z "$DERIVED_DATA" ]; then
        DERIVED_DATA=".build"
    fi

    # If platform is still empty, set it to the default value
    if [ -z "$PLATFORM" ]; then
        PLATFORM="iOS"
    fi

    # Get altool type and destination from platform
    APP_TYPE="$(get_altool_type "$PLATFORM")"
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
    
    local api_key_path="$AUTH_KEY_PATH/AuthKey_${AUTH_KEY_ID}.p8"

    # Command construction
    local xcode_cmd="xcodebuild archive -project '$PROJECT' -scheme '$SCHEME'"
    xcode_cmd="$xcode_cmd -destination '$DESTINATION' -derivedDataPath '$DERIVED_DATA'"
    xcode_cmd="$xcode_cmd -archivePath '$archive_path' -configuration '$CONFIG'"
    xcode_cmd="$xcode_cmd -authenticationKeyPath '$api_key_path' -authenticationKeyID '$AUTH_KEY_ID'"
    xcode_cmd="$xcode_cmd -authenticationKeyIssuerID '$AUTH_KEY_ISSUER'"
    xcode_cmd="$xcode_cmd -allowProvisioningUpdates -allowProvisioningDeviceRegistration"
    xcode_cmd="$xcode_cmd $OTHER_ARCHIVE_ARGS"

    # Execute command
    echo "Executing archive command:"
    echo "$xcode_cmd"

    # Create build directory if it doesn't exist
    mkdir -p "$DERIVED_DATA"

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

    # If archive succeeded, export the archive
    if [ $archive_status -eq 0 ]; then
        echo "Exporting archive..."
        
        local export_cmd="xcodebuild -exportArchive"
        export_cmd="$export_cmd -archivePath '$archive_path'"
        export_cmd="$export_cmd -exportOptionsPlist '$EXPORT_OPTIONS_PLIST'"
        export_cmd="$export_cmd -exportPath '$archive_path/Products'"
        export_cmd="$export_cmd -authenticationKeyPath '$api_key_path' -authenticationKeyID '$AUTH_KEY_ID'"
        export_cmd="$export_cmd -authenticationKeyIssuerID '$AUTH_KEY_ISSUER'"
        export_cmd="$export_cmd $OTHER_EXPORT_ARGS"

        # Execute export command
        echo "Executing export command:"
        echo "$export_cmd"

        # Construct pipe chain
        local export_pipe_cmd="$export_cmd 2>&1 | tee -a '$log_file'"

        # Execute pipe chain
        eval "$export_pipe_cmd"
        local export_status=$?
        return $export_status
    fi

    return $archive_status
}

# Uploads archive to TestFlight.
upload_to_testflight() {
    local archive_path="$1"
    local log_file="$2"
    
    # Find the IPA file
    local ipa_path=$(find "$archive_path/Products" -name "*.ipa" -print -quit)
    if [ -z "$ipa_path" ]; then
        echo "Error: No IPA file found in $archive_path/Products"
        return 1
    fi
    
    # Ideally we would do this with --upload-package, --upload-app is easier to use
    echo "Uploading to TestFlight..."
    local upload_cmd="xcrun altool --upload-app --type '$APP_TYPE' --file '$ipa_path'"
    upload_cmd="$upload_cmd --apiKey '$AUTH_KEY_ID'"
    upload_cmd="$upload_cmd --apiIssuer '$AUTH_KEY_ISSUER'"
    upload_cmd="$upload_cmd -API_PRIVATE_KEYS_DIR '$AUTH_KEY_PATH'"
    
    # Execute command with logging
    echo "Executing upload command:"
    echo "$upload_cmd"

    # Construct pipe chain
    local pipe_cmd="$upload_cmd 2>&1 | tee '$log_file'"

    # Execute pipe chain
    eval "$pipe_cmd"
    local upload_status=$?
    return $upload_status
}

# Parse and validate arguments
parse_args "$@"

# Create paths
ARCHIVE_PATH="${DERIVED_DATA}/${SCHEME}.xcarchive"
ARCHIVE_LOG="${DERIVED_DATA}/${SCHEME}_archive.log"
UPLOAD_LOG="${DERIVED_DATA}/${SCHEME}_upload.log"

# Archive the app
archive_app "$ARCHIVE_PATH" "$ARCHIVE_LOG"
ARCHIVE_STATUS=$?

# Report archive status and upload if successful
if [ $ARCHIVE_STATUS -eq 0 ]; then
    echo "Archive completed successfully"
    
    # Upload to TestFlight
    upload_to_testflight "$ARCHIVE_PATH" "$UPLOAD_LOG"
    UPLOAD_STATUS=$?
    
    if [ $UPLOAD_STATUS -eq 0 ]; then
        echo "Upload to TestFlight completed successfully"
    else
        echo "Upload to TestFlight failed"
        exit $UPLOAD_STATUS
    fi
else
    echo "Archive failed"
    exit $ARCHIVE_STATUS
fi

echo "Archive log: ${ARCHIVE_LOG}"
echo "Upload log: ${UPLOAD_LOG}"
exit 0 
