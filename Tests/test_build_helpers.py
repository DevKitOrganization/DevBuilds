"""Exercise build and archive behavior using the real scripts and mocked external tools."""

import itertools
import shutil
import subprocess

from support import HelperTestCase, SOURCES


BUILD_HELPER = 'build_and_test.sh'
ARCHIVE_HELPER = 'archive_and_export.sh'
BUILD_OPTIONS = [
    '-a', '--action', '-b', '--build-path', '-c', '--config', '--derived-data-path',
    '-d', '--destination', '-p', '--project', '-s', '--scheme', '--source-packages-path',
    '-t', '--test-plan', '--test-products-path',
]
ARCHIVE_OPTIONS = [
    '--auth-key-id', '--auth-key-issuer-id', '--auth-key-path', '-b', '--build-path',
    '-c', '--config', '--derived-data-path', '-e', '--export-options-plist', '--platform',
    '-p', '--project', '-s', '--scheme', '--source-packages-path',
]


class BuildHelperTests(HelperTestCase):
    def test_build_state_paths(self):
        cases = [
            ({}, [], None, None),
            ({'XCODE_DERIVED_DATA_PATH': 'env derived',
              'XCODE_SOURCE_PACKAGES_PATH': 'env packages'}, [], 'env derived', 'env packages'),
            ({}, ['--derived-data-path', 'cli derived', '--source-packages-path', 'cli packages'],
             'cli derived', 'cli packages'),
            ({'XCODE_DERIVED_DATA_PATH': 'env derived',
              'XCODE_SOURCE_PACKAGES_PATH': 'env packages'},
             ['--derived-data-path', 'cli derived', '--source-packages-path', 'cli packages'],
             'cli derived', 'cli packages'),
            ({}, ['--derived-data-path', 'custom derived'], 'custom derived', None),
            ({}, ['--source-packages-path', 'custom packages'], None, 'custom packages'),
            ({'XCODE_DERIVED_DATA_PATH': '', 'XCODE_SOURCE_PACKAGES_PATH': ''}, [], None, None),
        ]
        actions = ('build', 'build-for-testing', 'test', 'test-without-building', 'archive')
        for action, (environment, options, derived, packages) in itertools.product(actions, cases):
            with self.subTest(action=action, options=options, environment=environment):
                self.reset_case()
                helper = ARCHIVE_HELPER if action == 'archive' else BUILD_HELPER
                extra = [] if action == 'archive' else ['--action', action]
                result = self.run_helper(helper, [*extra, *options], environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.calls()
                arguments = calls[0]['arguments']
                self.assertEqual(arguments[0], action)
                self.assert_option(arguments, '-derivedDataPath',
                                   derived or str(self.output / 'DerivedData'))
                if packages is None:
                    self.assertNotIn('-clonedSourcePackagesDirPath', arguments)
                else:
                    self.assert_option(arguments, '-clonedSourcePackagesDirPath', packages)
                configuration = 'Release' if action == 'archive' else 'Debug'
                self.assert_option(arguments, '-configuration', configuration)
                self.assertTrue(all(call['unbuffered'] == 'YES' for call in calls))
                if action == 'archive':
                    archive = str(self.output / 'Example.xcarchive')
                    self.assert_option(arguments, '-archivePath', archive)
                    exported = calls[1]['arguments']
                    self.assertEqual(exported[0], '-exportArchive')
                    self.assert_option(exported, '-archivePath', archive)
                    self.assert_option(exported, '-exportPath', archive + '/Products')
                    self.assertNotIn('-derivedDataPath', exported)
                    self.assertNotIn('-clonedSourcePackagesDirPath', exported)
                    logs = ['Example_archive.log', 'Example_export.log']
                else:
                    self.assert_option(arguments, '-resultBundlePath',
                                       str(self.output / ('Example_' + action + '.xcresult')))
                    logs = ['Example_' + action + '.log']
                for log in logs:
                    self.assertIn('Mock Xcode output', (self.output / log).read_text())

    def test_build_path_environment_and_default(self):
        for helper in (BUILD_HELPER, ARCHIVE_HELPER):
            for build_path in (None, 'environment output'):
                with self.subTest(helper=helper, build_path=build_path):
                    self.reset_case()
                    environment = dict(self.environment)
                    environment.update(XCODE_ACTION='build', XCODE_SCHEME='Example',
                                       XCODE_PROJECT='Example.xcodeproj',
                                       XCODE_DESTINATION='platform=iOS',
                                       APP_STORE_CONNECT_API_KEY_ID='key',
                                       APP_STORE_CONNECT_API_ISSUER_ID='issuer',
                                       APP_STORE_CONNECT_API_KEY_PATH='key.p8',
                                       XCODE_EXPORT_OPTIONS_PLIST='export.plist')
                    if build_path:
                        environment['XCODE_BUILD_PATH'] = build_path
                    result = subprocess.run(
                        ['/bin/bash', str(SOURCES / helper)], cwd=self.root, env=environment,
                        capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assert_option(self.calls()[0]['arguments'], '-derivedDataPath',
                                       (build_path or '.build') + '/DerivedData')

    def test_test_plan_and_test_products(self):
        result = self.run_helper(options=['--action', 'test', '--test-plan', 'Example Test Plan'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_option(self.calls()[0]['arguments'], '-testPlan', 'Example Test Plan')
        self.reset_case()
        result = self.run_helper(options=['--action', 'test-without-building',
                                         '--test-products-path', 'Example Test Products'])
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = self.calls()[0]['arguments']
        self.assert_option(arguments, '-testProductsPath', 'Example Test Products')
        for option in ('-project', '-scheme', '-configuration'):
            self.assertNotIn(option, arguments)

    def test_every_value_option_rejects_missing_empty_or_option_values(self):
        for helper, options in ((BUILD_HELPER, BUILD_OPTIONS), (ARCHIVE_HELPER, ARCHIVE_OPTIONS)):
            invalid_values = ([], [''], ['--scheme'], ['--unknown'])
            for option, suffix in itertools.product(options, invalid_values):
                with self.subTest(helper=helper, option=option, suffix=suffix):
                    self.reset_case()
                    result = self.run_helper(helper, [option, *suffix])
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(option + ' requires a nonempty value', result.stderr)
                    self.assertEqual(list(self.capture.iterdir()), [])
                    self.assertFalse(self.output.exists())

    def test_unknown_options_and_invalid_actions_fail_before_output(self):
        for helper, options in ((BUILD_HELPER, ['--unknown']),
                                (ARCHIVE_HELPER, ['--unknown']),
                                (BUILD_HELPER, ['--action', 'invalid'])):
            with self.subTest(helper=helper, options=options):
                self.reset_case()
                result = self.run_helper(helper, options)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())
                self.assertEqual(self.calls(), [])

    def test_all_extra_flags_preserve_literal_arguments_and_are_last(self):
        flags = ("SETTING='with spaces' '' \"O'Reilly\" 'LITERAL=$(touch sentinel)' "
                 "'REGEX=\\d' *.txt")
        expected = ['SETTING=with spaces', '', "O'Reilly", 'LITERAL=$(touch sentinel)',
                    r'REGEX=\d', '*.txt']
        (self.root / 'match.txt').touch()
        targets = [(BUILD_HELPER, 'OTHER_XCODE_FLAGS', 'xcodebuild'),
                   (BUILD_HELPER, 'OTHER_XCBEAUTIFY_FLAGS', 'xcbeautify'),
                   (ARCHIVE_HELPER, 'OTHER_ARCHIVE_FLAGS', 'xcodebuild'),
                   (ARCHIVE_HELPER, 'OTHER_EXPORT_FLAGS', 'xcodebuild'),
                   (ARCHIVE_HELPER, 'OTHER_XCBEAUTIFY_FLAGS', 'xcbeautify')]
        for helper, variable, command in targets:
            with self.subTest(variable=variable):
                self.reset_case()
                result = self.run_helper(helper, environment={variable: flags})
                self.assertEqual(result.returncode, 0, result.stderr)
                observations = self.calls(command)
                if variable == 'OTHER_EXPORT_FLAGS':
                    observations = observations[1:]
                elif variable == 'OTHER_ARCHIVE_FLAGS':
                    observations = observations[:1]
                self.assertTrue(observations)
                for observation in observations:
                    self.assertEqual(observation['arguments'][-len(expected):], expected)
                self.assertFalse((self.root / 'sentinel').exists())
                self.reset_case()
                result = self.run_helper(helper, environment={
                    variable: 'PRIVATE_VALUE=$(touch sentinel)',
                })
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('PRIVATE_VALUE', result.stderr)
                self.assertFalse(self.output.exists())
                self.assertEqual(list(self.capture.iterdir()), [])
                self.assertFalse((self.root / 'sentinel').exists())

    def test_parameter_values_and_logged_commands_preserve_argument_boundaries(self):
        value = "Example's ; $(touch sentinel) \\\nsecond line"
        for helper in (BUILD_HELPER, ARCHIVE_HELPER):
            with self.subTest(helper=helper):
                self.reset_case()
                options = ['--project', value, '--derived-data-path', value,
                           '--source-packages-path', value]
                if helper == BUILD_HELPER:
                    options += ['--destination', value, '--test-products-path', value]
                else:
                    options += ['--auth-key-path', value, '--export-options-plist', value]
                environment = {'OTHER_XCODE_FLAGS': "''", 'OTHER_ARCHIVE_FLAGS': "''",
                               'OTHER_EXPORT_FLAGS': "''"}
                result = self.run_helper(helper, options, environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = self.calls()
                for observation in expected:
                    self.assertIn(value, observation['arguments'])
                    self.assertEqual(observation['arguments'][-1], '')
                lines = [line for line in result.stdout.splitlines()
                         if line.startswith('NSUnbufferedIO=YES ')]
                self.assertEqual(len(lines), len(expected))
                (self.capture / 'xcodebuild.jsonl').unlink()
                for line in lines:
                    subprocess.run(['/bin/bash', '-c', line], cwd=self.root, env=self.environment,
                                   check=True, capture_output=True, text=True, timeout=10)
                self.assertEqual(self.calls(), expected)
                self.assertFalse((self.root / 'sentinel').exists())

    def test_pipeline_failure_precedence_and_export_gating(self):
        modes = [('build', True), ('build', False), ('archive', True),
                 ('archive', False), ('export', True)]
        for stage, formatted in modes:
            formatter_statuses = (0, 37) if formatted and stage != 'export' else (0,)
            for xcode, tee, formatter in itertools.product((0, 23), (0, 31), formatter_statuses):
                statuses = (xcode, tee, formatter)
                with self.subTest(stage=stage, formatted=formatted, statuses=statuses):
                    self.reset_case()
                    environment = {'TEST_' + stage.upper() + '_STATUS': str(xcode),
                                   'TEST_' + stage.upper() + '_TEE_STATUS': str(tee),
                                   'TEST_FORMATTER_STATUS': str(formatter)}
                    helper = BUILD_HELPER if stage == 'build' else ARCHIVE_HELPER
                    options = ['--disable-xcbeautify'] if stage == 'build' and not formatted else []
                    mock_formatter = self.commands / 'xcbeautify'
                    if stage == 'archive' and not formatted:
                        mock_formatter.rename(self.commands / 'unused-formatter')
                    try:
                        result = self.run_helper(helper, options, environment)
                    finally:
                        if (self.commands / 'unused-formatter').exists():
                            (self.commands / 'unused-formatter').rename(mock_formatter)
                    expected = xcode or formatter or tee
                    self.assertEqual(result.returncode, expected, result.stderr)
                    if stage == 'archive' and expected:
                        self.assertEqual(len(self.calls()), 1)
                    if stage == 'export':
                        self.assertEqual(len(self.calls()), 2)
                    if not formatted:
                        self.assertEqual(self.calls('xcbeautify'), [])

    def test_missing_formatter_still_runs_build_and_writes_log(self):
        (self.commands / 'xcbeautify').unlink()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls('xcbeautify'), [])
        self.assertIn('Mock Xcode output', (self.output / 'Example_build.log').read_text())

    def test_utilities_source_quietly_without_changing_shell_options_or_directory(self):
        copied = self.root / 'helpers with spaces'
        shutil.copytree(SOURCES, copied)
        program = '''before_options="$(set +o)"
before_directory="$PWD"
source "$1" || exit 1
[[ "$(set +o)" == "$before_options" && "$PWD" == "$before_directory" ]] || exit 1
parse_extra_flags "'with spaces' ''" || exit 1
[[ ${#PARSED_EXTRA_FLAGS[@]} -eq 2 ]] || exit 1
[[ "${PARSED_EXTRA_FLAGS[0]}" == 'with spaces' && -z "${PARSED_EXTRA_FLAGS[1]}" ]] || exit 1
'''
        result = subprocess.run(['/bin/bash', '-c', program, 'test',
                                 str(copied / 'shell_utilities.sh')], cwd=self.root,
                                env=self.environment, capture_output=True, text=True, timeout=10)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        for helper in (BUILD_HELPER, ARCHIVE_HELPER):
            with self.subTest(helper=helper):
                self.reset_case()
                result = self.run_helper(helper, sources=copied)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_shell_syntax(self):
        for source in sorted(SOURCES.glob('*.sh')):
            with self.subTest(source=source.name):
                result = subprocess.run(['/bin/bash', '-n', str(source)], capture_output=True,
                                        text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
