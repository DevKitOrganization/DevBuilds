# Shell Style Guide

Write shell scripts for someone who usually works in Swift or Python. The reader should be
able to understand the workflow, follow values between functions, and see how failures are
handled without mentally expanding compact shell expressions. Favor clarity over brevity.

Apply these conventions to new scripts and code being changed. Refactor existing scripts in
focused changes that preserve behavior and receive the relevant validation.


## Structure Around Meaningful Operations

Factor important work into named functions, even when each function is called only once.
Functions provide names for concepts and keep implementation details out of the main workflow.
For example, downloading a release, validating an archive, and installing it are separate steps.

  - Give each function one coherent responsibility. Avoid functions that mix unrelated steps.
  - Use descriptive `snake_case` names, usually starting with a verb: `download_runner_archive`.
    Preserve an established namespace prefix in shared libraries.
  - Keep the main workflow short enough to read as a sequence of operations.
  - Use a `main` function when argument handling, state, or branching needs a scope. A short
    sequence of function calls at the bottom is also fine.
  - Keep executable setup near the entry point so execution order is easy to see. Sourced
    libraries should define helpers without starting work unexpectedly.
  - Extract a function when its name explains a meaningful operation. Do not wrap every
    individual command merely to make it a function.


## Document Every Function

Place a comment immediately above each function describing what it does. A short sentence is
enough for a simple helper. Add detail when a caller needs to know about:

  - Arguments, especially optional values or values with constraints.
  - Output written to standard output and the meaning of return statuses.
  - Global configuration read or changed, files modified, and other side effects.
  - Ownership, locks, cleanup, and ordering requirements.

Use ordinary prose; a fixed documentation template is unnecessary. Inside a function, explain
why a step is needed or why the shell behavior is surprising. Avoid narrating obvious commands.

    # Write a complete state file, then replace the destination atomically.
    # The caller must hold the state lock; atomic replacement does not serialize writers.
    # Return nonzero if writing or replacement fails.
    write_state_file() {
        local destination="$1"
        local state_json="$2"
        local temporary_file="${destination}.tmp.$$"

        if ! printf '%s\n' "$state_json" > "$temporary_file"; then
            rm -f "$temporary_file"
            return 1
        fi

        if ! mv -f "$temporary_file" "$destination"; then
            rm -f "$temporary_file"
            return 1
        fi
    }


## Make Data Flow Visible

  - Give positional arguments descriptive local names at the start of a function.
  - Declare one local variable per line. Keep temporary values local.
  - Use lowercase `snake_case` for local variables. Reserve uppercase names for environment
    configuration and established script-wide constants or shared state.
  - Prefer explicit arguments over reading a caller's local variables. Bash uses dynamic
    scope, so a helper can accidentally depend on a local variable in its caller.
  - When shared script state is useful, initialize it in one obvious place and document which
    functions change it. Avoid generic global names such as `result` or `value`.
  - Use standard output for returned data and standard error for diagnostics when callers
    capture output. Use return statuses to communicate success or failure.
  - Separate a local declaration from command substitution so `local` does not hide the
    command's exit status.

    # Print the canonical path of an existing directory. Return nonzero if it is inaccessible.
    resolve_directory() {
        local directory="$1"

        (
            if ! cd "$directory"; then
                return 1
            fi

            pwd -P
        )
    }

At the call site, make the failure path explicit:

    local resolved_directory
    if ! resolved_directory="$(resolve_directory "$directory")"; then
        printf 'Cannot resolve directory: %s\n' "$directory" >&2
        return 1
    fi


## Use Explicit Control Flow

Use expanded `if`, `case`, and loop blocks. Prefer early returns for invalid input and failed
prerequisites so the main operation stays easy to follow.

    if [[ ! -f "$configuration_file" ]]; then
        printf 'Missing configuration: %s\n' "$configuration_file" >&2
        return 1
    fi

Avoid chains such as `[ -f "$configuration_file" ] || { log_error; return 1; }`. A reader
should not have to interpret several exit statuses to understand a branch.

  - Use `[[ ... ]]` for new Bash conditions and `case` for selecting among named alternatives.
  - Put one command per line; expand branch bodies even when they contain one command.
  - Keep related steps together, with blank lines between distinct operations.
  - Use four spaces for indentation and aim for lines under 100 characters.
  - Prefer a named intermediate value over nested substitutions or dense parameter expansion.
    Simple defaults such as `"${RUNNER_VERSION:-}"` are fine.


## Keep Commands Readable

Quote variable expansions used as arguments. Use direct command invocations and arrays for
optional arguments. Preserve argument boundaries instead of assembling shell source in strings
and executing it with `eval`.

Put long invocations on multiple lines, grouping an option with its value:

    local download_arguments=(
        --fail
        --silent
        --show-error
        --location
        --connect-timeout 15
        --max-time 300
        --output "$archive_path"
    )

    if [[ -n "$user_agent" ]]; then
        download_arguments+=(--user-agent "$user_agent")
    fi

    if ! curl "${download_arguments[@]}" "$download_url"; then
        printf 'Runner archive download failed\n' >&2
        return 1
    fi

Format substantial JSON filters over multiple lines. Move substantial embedded Python or other
programs into their own files, and include those files in provisioning and validation. Shell
should make the sequence of external operations easy to understand.


## Make Failure and Cleanup Intentional

Check failures explicitly when they determine what happens next. Use `return` in helpers and
let the entry point decide the process exit status; helpers whose purpose is to terminate the
script must say so in their comments.

  - Treat `set -euo pipefail` as a script-level choice, not a substitute for error handling.
    In particular, calling a function as an `if` condition disables `errexit` within it.
    Operations that must stop on failure need explicit checks in such functions.
  - Use `if ! command; then` when only success or failure matters. To preserve the original
    failure status, use `if command; then ... else` and capture `$?` first in the `else` branch.
  - Explain deliberately ignored failures. Avoid blanket `|| true` that hides unexpected errors.
  - Put substantial trap handling in a documented cleanup function. Make resource ownership
    clear and preserve the original failure status when cleanup runs.
  - Validate inputs before side effects. Bound retries and network waits. Preserve working
    configuration and useful diagnostics when an operation fails.


## Compatibility and Review

Support macOS's built-in Bash 3.2 unless a different runtime is explicitly installed and selected.
Use BSD-compatible command options.

During review, check that the workflow is clear from the function calls, each function explains
its purpose, and inputs, state changes, and failure paths are easy to find. Run shell syntax
checks for changed scripts and the relevant mocked tests for behavioral refactors.
