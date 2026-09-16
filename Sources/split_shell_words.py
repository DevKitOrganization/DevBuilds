#!/usr/bin/python3
"""Parse extra build flags without executing shell syntax or exposing input in errors."""

import shlex
import sys


def prepare_flag_string(flag_string: str) -> str:
    """Reject shell operations and normalize Bash's double-quoted dollar/backtick escapes."""
    if any(character in flag_string for character in "\0\r\n"):
        raise ValueError("NUL and newlines are not supported")

    quote = None
    escaped = False
    characters = []
    for character in flag_string:
        if escaped:
            # shlex retains these backslashes; Bash removes them. shlex never expands the
            # resulting dollar/backtick, so removing the escape preserves the literal argument.
            if quote == '"' and character in "$`":
                characters.pop()
            characters.append(character)
            escaped = False
            continue

        if character == "\\" and quote != "'":
            escaped = True
        elif quote == "'":
            if character == "'":
                quote = None
        elif character in "$`":
            raise ValueError("shell expansion is not supported")
        elif quote == '"':
            if character == '"':
                quote = None
        elif character in "'\"":
            quote = character
        elif character in "|&;<>()":
            raise ValueError("shell operators are not supported")

        characters.append(character)

    return "".join(characters)


def main() -> int:
    """Print NUL-delimited arguments for Bash arrays, or report invalid syntax."""
    if len(sys.argv) != 2:
        print("Expected one flag string", file=sys.stderr)
        return 1

    try:
        arguments = shlex.split(prepare_flag_string(sys.argv[1]))
    except ValueError as error:
        # Our validation and shlex errors describe syntax without including private flag values.
        print("Invalid extra flags: {}".format(error), file=sys.stderr)
        return 1

    # A delimiter after every argument distinguishes an empty argument from no arguments.
    for argument in arguments:
        sys.stdout.write(argument + "\0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
