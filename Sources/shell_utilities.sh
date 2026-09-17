#!/bin/bash

# Shared helpers for the build and archive entry points. Source this file; it runs no setup.

# Return the first command's failure status, or the rightmost failure from the remaining commands.
# Pass the captured PIPESTATUS elements in order; return zero when all commands succeed.
check_pipeline_status() {
    local first_command_status="$1"
    local pipeline_status=0
    local command_status

    if [[ "$first_command_status" -ne 0 ]]; then
        return "$first_command_status"
    fi
    shift

    for command_status in "$@"; do
        if [[ "$command_status" -ne 0 ]]; then
            pipeline_status="$command_status"
        fi
    done
    return "$pipeline_status"
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

    if ! script_directory="$(dirname "${BASH_SOURCE[0]}")"; then
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

