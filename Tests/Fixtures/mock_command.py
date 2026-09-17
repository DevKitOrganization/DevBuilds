#!/usr/bin/python3
"""Stand in for Xcode, tee, or xcbeautify without performing builds or contacting services."""

import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    """Record arguments, consume pipeline input, and return the configured stage's status."""
    command = Path(sys.argv[0]).name
    arguments = sys.argv[1:]
    capture = Path(os.environ['TEST_CAPTURE']) / (command + '.jsonl')
    with capture.open('a') as output:
        output.write(json.dumps({
            'arguments': arguments,
            'unbuffered': os.environ.get('NSUnbufferedIO'),
        }) + '\n')

    if command == 'xcodebuild':
        if arguments[0] == '-exportArchive':
            stage = 'export'
        elif arguments[0] == 'archive':
            stage = 'archive'
        else:
            stage = 'build'
        print('Mock Xcode output')
        status_key = 'TEST_' + stage.upper() + '_STATUS'
    elif command == 'tee':
        # Use the system tee so the tests still exercise log creation and pipeline forwarding.
        result = subprocess.run(['/usr/bin/tee', *arguments], check=False)
        if result.returncode:
            return result.returncode
        if arguments[0].endswith('_export.log'):
            stage = 'export'
        elif arguments[0].endswith('_archive.log'):
            stage = 'archive'
        else:
            stage = 'build'
        status_key = 'TEST_' + stage.upper() + '_TEE_STATUS'
    else:
        sys.stdout.write(sys.stdin.read())
        status_key = 'TEST_FORMATTER_STATUS'
    return int(os.environ.get(status_key, '0'))


if __name__ == '__main__':
    sys.exit(main())
