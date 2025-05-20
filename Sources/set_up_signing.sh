#!/bin/bash

###
# This script sets up code signing certificates and provisioning profiles for iOS development.

# Enable pipefail to ensure we get the correct exit status from pipelines
set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --certificate     Base64-encoded Apple Distribution certificate"
    echo "  --password        Password for the Apple Distribution certificate"
    echo "  --profiles        One or more Base64-encoded provisioning profiles"
    echo "  --temp-dir        Directory for temporary files"
    exit 1
}

# Parse command line arguments
CERTIFICATE=""
PASSWORD=""
PROFILES=()
TEMP_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --certificate)
            CERTIFICATE="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --profiles)
            shift
            while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do
                PROFILES+=("$1")
                shift
            done
            ;;
        --temp-dir)
            TEMP_DIR="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown parameter: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$CERTIFICATE" ]; then
    echo "Error: Missing required parameter --certificate"
    usage
fi

if [ -z "$PASSWORD" ]; then
    echo "Error: Missing required parameter --password"
    usage
fi

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "Error: Missing required parameter --profiles"
    usage
fi

if [ -z "$TEMP_DIR" ]; then
    echo "Error: Missing required parameter --temp-dir"
    usage
fi

# Create temporary directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Set up paths for temporary files
CERTIFICATE_PATH="$TEMP_DIR/distribution.p12"
KEYCHAIN_PATH="$TEMP_DIR/build.keychain"
KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

# Clean up any existing files
rm -f "$CERTIFICATE_PATH" "$KEYCHAIN_PATH"

# Decode and save the distribution certificate
echo "Setting up distribution certificate..."
echo "$CERTIFICATE" | base64 --decode --output "$CERTIFICATE_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to decode distribution certificate"
    exit 1
fi

# Create a new Keychain
echo "Creating new Keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create keychain"
    exit 1
fi

# Set Keychain settings
security set-keychain-settings -lut 3600 -u "$KEYCHAIN_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set keychain settings"
    exit 1
fi

# Unlock the Keychain
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to unlock the Keychain"
    exit 1
fi

# Import the certificate into the Keychain
echo "Importing certificate into Keychain..."
security import "$CERTIFICATE_PATH" \
    -k "$KEYCHAIN_PATH" \
    -P "$PASSWORD" \
    -A \
    -t cert \
    -f pkcs12
if [ $? -ne 0 ]; then
    echo "Error: Failed to import certificate into Keychain"
    exit 1
fi

security set-key-partition-list \
    -S apple-tool:,apple: \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set key partition for Keychain"
    exit 1
fi

security list-keychain -d user -s "$KEYCHAIN_PATH"

# Install the provisioning profiles
echo "Installing provisioning profiles..."
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles/

for profile in "${PROFILES[@]}"; do
    PROFILE_PATH="$TEMP_DIR/profile_$(openssl rand -hex 4).mobileprovision"
    echo "Installing profile $(basename $PROFILE_PATH)"

    echo "$profile" | base64 --decode --output "$PROFILE_PATH"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to decode provisioning profile"
        exit 1
    fi

    cp "$PROFILE_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install provisioning profile"
        exit 1
    fi

    rm -f "$PROFILE_PATH"
done

echo "Code signing setup completed successfully"
