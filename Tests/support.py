"""Isolated command fixtures shared by the helper integration tests."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCES = Path(__file__).resolve().parents[1] / 'Sources'
FIXTURES = Path(__file__).resolve().parent / 'Fixtures'


class HelperTestCase(unittest.TestCase):
    """Run the real shell helpers with mock commands and a controlled environment."""

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix='devbuilds-tests-')
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.commands = self.root / 'bin'
        self.commands.mkdir()
        for command in ('xcodebuild', 'tee', 'xcbeautify'):
            path = self.commands / command
            shutil.copyfile(FIXTURES / 'mock_command.py', path)
            path.chmod(0o755)
        self.capture = self.root / 'capture'
        self.output = self.root / 'job output'
        self.reset_case()

    def reset_case(self):
        """Reset mock observations, build output, and configuration between table-driven cases."""
        for path in (self.capture, self.output):
            if path.exists():
                shutil.rmtree(path)
        self.capture.mkdir()
        # Do not inherit developer signing, build, or extra-flag configuration from the host.
        self.environment = {
            'PATH': str(self.commands) + ':/usr/bin:/bin:/usr/sbin:/sbin',
            'TEST_CAPTURE': str(self.capture),
            'TMPDIR': str(self.root),
        }

    def run_helper(self, helper='build_and_test.sh', options=(), environment=None, sources=SOURCES):
        """Execute a helper with valid baseline options, allowing later options to override them."""
        arguments = ['--build-path', str(self.output), '--scheme', 'Example',
                     '--project', 'Example Project.xcodeproj']
        if helper == 'build_and_test.sh':
            arguments += [
                '--action', 'build', '--destination', 'platform=iOS Simulator,name=Example',
            ]
        else:
            arguments += ['--auth-key-id', 'key', '--auth-key-issuer-id', 'issuer',
                          '--auth-key-path', 'Example Key.p8',
                          '--export-options-plist', 'Export Options.plist']
        configured_environment = dict(self.environment)
        configured_environment.update(environment or {})
        return subprocess.run(
            ['/bin/bash', str(sources / helper), *arguments, *options],
            cwd=self.root, env=configured_environment, capture_output=True, text=True, timeout=10,
        )

    def calls(self, command='xcodebuild'):
        """Read observations for one mock command; different commands use separate capture files."""
        path = self.capture / (command + '.jsonl')
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text().splitlines()]

    def assert_option(self, arguments, option, expected):
        """Require exactly one occurrence of an option with its expected value."""
        self.assertEqual(arguments.count(option), 1, arguments)
        self.assertEqual(arguments[arguments.index(option) + 1], expected)
