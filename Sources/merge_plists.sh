#!/bin/bash

set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 output.plist input1.plist [input2.plist ...]"
    echo ""
    echo "Merges multiple property lists into a single output file."
    echo "The first argument is the output file, followed by two or more input files."
    exit 1
}

# Check if we have at least 3 arguments (output file + 2 input files)
if [ $# -lt 3 ]; then
    echo "Error: At least 3 arguments required (output file + 2 input files)"
    usage
fi

# Get the output file path
OUTPUT_FILE="$1"
shift

if [ -f "$OUTPUT_FILE" ]; then
    echo "Output file '$OUTPUT_FILE' exists. Deleting."
    rm "$OUTPUT_FILE"
fi

# Merge plists
for plist in "$@"; do
    if [ ! -f "$plist" ]; then
        echo "Error: Input file '$plist' does not exist"
        exit 1
    fi
    
    echo "Merging $(basename "$plist")..."
    /usr/libexec/PlistBuddy -c "Merge '$plist'" "$OUTPUT_FILE"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to merge '$plist'"
        exit 1
    fi
done

echo "Successfully merged plists into $OUTPUT_FILE" 
