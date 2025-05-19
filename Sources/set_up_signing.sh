#!/bin/bash

###
# This script sets up code signing certificates and provisioning profiles for iOS development.

# Enable pipefail to ensure we get the correct exit status from pipelines
set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0"
    echo ""
    echo "This script requires the following environment variables to be set:"
    echo "  DISTRIBUTION_CERTIFICATE_BASE64     Base64-encoded Apple Distribution certificate"
    echo "  DISTRIBUTION_CERTIFICATE_PASSWORD   Password for the Apple Distribution certificate"
    echo "  PROVISIONING_PROFILE_BASE64         Base64-encoded provisioning profile"
    echo "  TEMP_DIR                            Directory for temporary files"
    exit 1
}

# Check if required environment variables are set
if [ -z "$DISTRIBUTION_CERTIFICATE_BASE64" ]; then 
    echo "Error: Missing required environment variable DISTRIBUTION_CERTIFICATE_BASE64"
    usage
elif [ -z "$DISTRIBUTION_CERTIFICATE_PASSWORD" ]; then
    echo "Error: Missing required environment variable DISTRIBUTION_CERTIFICATE_PASSWORD"
    usage
elif [ -z "$PROVISIONING_PROFILE_BASE64" ]; then
    echo "Error: Missing required environment variable PROVISIONING_PROFILE_BASE64"
    usage
elif [ -z "$TEMP_DIR" ]; then
    echo "Error: Missing required environment variable TEMP_DIR"
    usage
fi

# Create temporary directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Set up paths for temporary files
CERTIFICATE_PATH="$TEMP_DIR/distribution.p12"
PROVISIONING_PROFILE_PATH="$TEMP_DIR/profile.mobileprovision"
KEYCHAIN_PATH="$TEMP_DIR/build.keychain"
KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

# Clean up any existing files
rm -f "$CERTIFICATE_PATH" "$PROVISIONING_PROFILE_PATH" "$KEYCHAIN_PATH"

# Decode and save the distribution certificate
echo "Setting up distribution certificate..."
echo "$DISTRIBUTION_CERTIFICATE_BASE64" | base64 --decode --output "$CERTIFICATE_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to decode distribution certificate"
    exit 1
fi

# Decode and save the provisioning profile
echo "Setting up provisioning profile..."
echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode --output "$PROVISIONING_PROFILE_PATH"
if [ $? -ne 0 ]; then
    echo "Error: Failed to decode provisioning profile"
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
    -A -t cert \
    -f pkcs12 \
    -P "$DISTRIBUTION_CERTIFICATE_PASSWORD" \
    -k "$KEYCHAIN_PATH" \
    -T /usr/bin/codesign
if [ $? -ne 0 ]; then
    echo "Error: Failed to import certificate into Keychain"
    exit 1
fi

# Install the provisioning profile
echo "Installing provisioning profile..."
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles/
cp "$PROVISIONING_PROFILE_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/
if [ $? -ne 0 ]; then
    echo "Error: Failed to install provisioning profile"
    exit 1
fi
