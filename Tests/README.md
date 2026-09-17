# Tests

Run the suite from the repository root on macOS with the Python supplied by Xcode:

    python3 -m unittest discover -s Tests -v

The suite uses Python's standard library and macOS's built-in `/bin/bash`. It needs no additional
packages. The GitHub Actions workflow runs the same command on `macos-latest` for pushes and
pull requests.


## Coverage

  - Extra-flag parsing, including quotes, escapes, empty arguments, and rejected shell syntax.
  - Build and archive arguments, persistent build paths, defaults, and CLI/environment precedence.
  - Invalid options and flags failing before build output is created or commands are started.
  - Literal parameter values and shell-escaped command logging.
  - Pipeline failure precedence and preventing export after a failed archive.
  - Shared utility loading from paths containing spaces, and shell syntax checks.

Each integration test uses a temporary directory, a controlled environment, and mock `xcodebuild`,
`tee`, and `xcbeautify` commands. The mock `tee` forwards to the system command to exercise log
creation. Temporary state is cleaned up even when a test fails.

These tests do not build applications, use signing credentials, or contact external services.
They verify the scripts' behavior and argument handling; they do not establish that Xcode accepts
an invocation or that a real build, test, archive, or export succeeds. Signing setup and plist
merging are not covered beyond shell syntax checks.
