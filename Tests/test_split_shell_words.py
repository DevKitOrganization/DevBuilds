"""Behavioral tests for the executable extra-flag parser."""

import subprocess
import unittest

from support import SOURCES


class SplitShellWordsTests(unittest.TestCase):
    def test_supported_arguments(self):
        cases = [
            ('', []), ('   ', []),
            ('-skipMacroValidation -parallel-testing-enabled NO',
             ['-skipMacroValidation', '-parallel-testing-enabled', 'NO']),
            ('"APP_CONFIGURATION=with spaces"', ['APP_CONFIGURATION=with spaces']),
            ("SETTING='with spaces'", ['SETTING=with spaces']),
            ("'' \"\" end", ['', '', 'end']),
            (r'escaped\ space', ['escaped space']),
            (r'"escaped\"quote"', ['escaped"quote']),
            ('"O\'Reilly"', ["O'Reilly"]),
            ("'SETTING=$literal'", ['SETTING=$literal']),
            (r'SETTING=\$literal', ['SETTING=$literal']),
            ("'SETTING=$(literal)'", ['SETTING=$(literal)']),
            ("'SETTING=`literal`'", ['SETTING=`literal`']),
            ("'SETTING=a|b;c>file'", ['SETTING=a|b;c>file']),
            (r"'SETTING=\d'", [r'SETTING=\d']),
            (r'"SETTING=\d"', [r'SETTING=\d']),
            (r'"SETTING=back\\slash"', [r'SETTING=back\slash']),
            ('prefix"middle space"suffix', ['prefixmiddle spacesuffix']),
            (r'"SETTING=\$literal"', ['SETTING=$literal']),
            (r'"SETTING=\`literal\`"', ['SETTING=`literal`']),
            ("'SETTING=café 🚀'", ['SETTING=café 🚀']),
            ('*.txt ~', ['*.txt', '~']), ('first\tsecond', ['first', 'second']),
            (r'\| \; \< \> \( \) \&', ['|', ';', '<', '>', '(', ')', '&']),
        ]
        for flags, expected in cases:
            with self.subTest(flags=flags):
                result = subprocess.run([str(SOURCES / 'split_shell_words.py'), flags],
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, ''.join(argument + '\0' for argument in expected))
                self.assertEqual(result.stderr, '')

    def test_rejected_syntax_does_not_expose_input(self):
        cases = ['"unterminated', "'unterminated", 'trailing\\', '$HOME', '${HOME}',
                 '$(touch sentinel)', '`touch sentinel`', '"$HOME"', 'foo | tee file',
                 'foo > file', 'foo < file', 'foo; touch file', 'foo && command',
                 'foo (bar)', 'first\nsecond', 'first\rsecond']
        for flags in cases:
            with self.subTest(flags=flags):
                result = subprocess.run(
                    [str(SOURCES / 'split_shell_words.py'), 'PRIVATE_VALUE=' + flags],
                    capture_output=True, text=True, timeout=5,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertNotIn('PRIVATE_VALUE', result.stderr)

    def test_requires_one_flag_string(self):
        for arguments in ([], ['one', 'two']):
            with self.subTest(arguments=arguments):
                result = subprocess.run([str(SOURCES / 'split_shell_words.py'), *arguments],
                                        capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
