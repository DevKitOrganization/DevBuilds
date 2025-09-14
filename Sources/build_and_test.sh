#!/bin/bash

###
# This script build and tests an Xcode project or Swift Package using xcodebuild.

set -o pipefail

# Displays usage information and exits.
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --action ACTION        Action to perform (default: build, options: build,"
    echo "                             build-for-testing, test, test-without-building)"
    echo "  -b, --build-path PATH      Build products path (default: .build)"
    echo "  -c, --config CONFIG        Build configuration (default: Debug)"
    echo "  -d, --destination DEST     Destination device specifier (required)"
    echo "  --disable-xcbeautify       Disables use of xcbeautify"
    echo "  -h, --help                 Show this help message"
    echo "  -p, --project PROJECT      Xcode project path (required)"
    echo "  -s, --scheme SCHEME        Scheme name (required)"
    echo "  -t, --test-plan PLAN       Test plan to use (required for test actions)"
    echo "  --test-products-path PATH  Test products path for test-without-building"
    echo ""
    echo "Environment variables:"
    echo "  OTHER_XCODE_FLAGS          Additional flags to pass to xcodebuild"
    echo "  OTHER_XCBEAUTIFY_FLAGS     Additional flags to pass to xcbeautify"
    echo "  XCODE_ACTION               Action to perform"
    echo "  XCODE_BUILD_PATH           Build products path"
    echo "  XCODE_CONFIG               Build configuration"
    echo "  XCODE_DESTINATION          Destination device specifier"
    echo "  XCODE_PROJECT              Xcode project path"
    echo "  XCODE_SCHEME               Scheme name"
    echo "  XCODE_TEST_PLAN            Test plan to use"
    echo "  XCODE_TEST_PRODUCTS_PATH   Test products path"
    exit 1
}

# Parses arguments and validates parameters.
parse_args() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--action)
                ACTION="$2"
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
            -d|--destination)
                DESTINATION="$2"
                shift 2
                ;;
            --disable-xcbeautify)
                DISABLE_XCBEAUTIFY="true"
                shift
                ;;
            -h|--help)
                usage
                ;;
            -p|--project)
                PROJECT="$2"
                shift 2
                ;;
            -s|--scheme)
                SCHEME="$2"
                shift 2
                ;;
            -t|--test-plan)
                TEST_PLAN="$2"
                shift 2
                ;;
            --test-products-path)
                TEST_PRODUCTS_PATH="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Set values from environment variables if not set by command line
    ACTION="${ACTION:-$XCODE_ACTION}"
    CONFIG="${CONFIG:-$XCODE_CONFIG}"
    BUILD_PATH="${BUILD_PATH:-$XCODE_BUILD_PATH}"
    DESTINATION="${DESTINATION:-$XCODE_DESTINATION}"
    PROJECT="${PROJECT:-$XCODE_PROJECT}"
    SCHEME="${SCHEME:-$XCODE_SCHEME}"
    TEST_PLAN="${TEST_PLAN:-$XCODE_TEST_PLAN}"
    TEST_PRODUCTS_PATH="${TEST_PRODUCTS_PATH:-$XCODE_TEST_PRODUCTS_PATH}"

    # If build path is still empty, set it to the default value
    if [ -z "$BUILD_PATH" ]; then
        BUILD_PATH=".build"
    fi

    # If config is still empty, set it to the default value
    if [ -z "$CONFIG" ]; then
        CONFIG="Debug"
    fi

    # If disabled xcbeautify is empty, set it to the default value
    if [ -z "$DISABLE_XCBEAUTIFY" ]; then
        DISABLE_XCBEAUTIFY="false"
    fi

    # Validate required parameters
    if [ -z "$ACTION" ]; then
        echo "Error: Action is required"
        usage
    elif [ -z "$DESTINATION" ]; then
        echo "Error: Destination is required"
        usage
    elif [ -z "$SCHEME" ]; then
        echo "Error: Scheme is required"
        usage
    fi
}

# Parse and validate arguments
parse_args "$@"

# Validate action
case "$ACTION" in
    "build"|"build-for-testing"|"test"|"test-without-building")
        XCODE_ACTION="$ACTION"
        ;;
    *)
        echo "Error: Action must be one of: build, build-for-testing, test, test-without-building"
        exit 1
        ;;
esac

mkdir -p "$BUILD_PATH"

# Create result bundle path
RESULT_BUNDLE="${BUILD_PATH}/${SCHEME}_${ACTION}.xcresult"

# Command construction
XCODE_CMD="NSUnbufferedIO=YES xcodebuild $XCODE_ACTION -disableAutomaticPackageResolution"

# Add standard parameters unless we're doing test-without-building with testProductsPath
if [ "$ACTION" != "test-without-building" ] || [ -z "$TEST_PRODUCTS_PATH" ]; then
    if [ -n "$PROJECT" ]; then
        XCODE_CMD="$XCODE_CMD -project '$PROJECT'"
    fi
    XCODE_CMD="$XCODE_CMD -scheme '$SCHEME'"
    XCODE_CMD="$XCODE_CMD -configuration '$CONFIG'"
    
    # Add test plan if specified and action is test
    if [ -n "$TEST_PLAN" ] && [ "$ACTION" = "test" ]; then
        XCODE_CMD="$XCODE_CMD -testPlan '$TEST_PLAN'"
    fi
fi

# Add common arguments (always included)
XCODE_CMD="$XCODE_CMD -destination '$DESTINATION'"
XCODE_CMD="$XCODE_CMD -resultBundlePath '$RESULT_BUNDLE'"
XCODE_CMD="$XCODE_CMD -derivedDataPath '$BUILD_PATH/DerivedData'"
XCODE_CMD="$XCODE_CMD $OTHER_XCODE_FLAGS"

# Add test products path if specified
if [ -n "$TEST_PRODUCTS_PATH" ]; then
    XCODE_CMD="$XCODE_CMD -testProductsPath '$TEST_PRODUCTS_PATH'"
fi

# Execute command
echo "Executing xcodebuild command:"
echo "$XCODE_CMD"

# Remove existing result bundle if it exists
rm -r "$RESULT_BUNDLE" 2>/dev/null || true

# Construct pipe chain
LOG_FILE="${BUILD_PATH}/${SCHEME}_${ACTION}.log"
PIPE_CMD="$XCODE_CMD 2>&1 | tee '$LOG_FILE'"

# Add xcbeautify to pipe chain if available
if [ "$DISABLE_XCBEAUTIFY" = "false" ]; then
    if command -v xcbeautify >/dev/null 2>&1; then
        PIPE_CMD="$PIPE_CMD | xcbeautify $OTHER_XCBEAUTIFY_FLAGS"
    fi
fi

# Execute pipe chain
eval "$PIPE_CMD"
CMD_STATUS=$?

# Report status and exit
if [ $CMD_STATUS -eq 0 ]; then
    echo "Command completed successfully"
else
    echo "Command failed with status $CMD_STATUS"
fi
echo "Log file: $LOG_FILE"
exit $CMD_STATUS
