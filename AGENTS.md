# Agent Guidelines

DevBuilds contains ready-to-use shell scripts for building, testing, and releasing apps and
packages with Apple’s Xcode tools, mainly on CI systems like GitHub Actions. Projects check out
DevBuilds and run the scripts in `Sources/`. The scripts need only Bash and Python 3, never Ruby or
another third-party runtime.


## Building and testing

  - `python3 -m unittest discover -s Tests -v` runs the tests, which use the fixtures in
    `Tests/Fixtures/` in place of Xcode’s tools.
  - Changes to a script’s inputs, environment variables, or outputs affect every project that
    uses it. Keep them backward compatible, or call out the
    break in `CHANGELOG.md`.


## Writing style

  - Follow the [Markdown Style Guide](Documentation/MarkdownStyleGuide.md) for all Markdown.
  - **Use typographic quotes and apostrophes, not straight ones,** in all Markdown, all code
    comments, and all user-facing messages:
      - Apostrophes: ’ (U+2019), as in “it’s”
      - Single quotes: ‘ (U+2018) and ’ (U+2019)
      - Double quotes: “ (U+201C) and ” (U+201D)

    Straight quotes (`'` and `"`) are still correct in code itself: string delimiters, code spans,
    code blocks, identifiers, and configuration files.


## Attribution

Never credit an agent or other code generation tool. Don’t add `Co-Authored-By` trailers or
“Generated with” lines to commits or pull requests, and don’t name an agent in file headers,
comments, or documentation. The programmer who uses a tool is accountable for the changes it
helped make.


## Commits and pull requests

A commit message is a short summary of what the commit does, then a blank line and a bulleted list
of the changes, close to what a changelog would say. Messages are plain text with lines of 72
characters or fewer. A pull request uses its commit message: the title is the summary, and the
body is the bullets.

Add an entry to `CHANGELOG.md` for changes that affect projects using DevBuilds.


## Code

Follow the [Shell Style Guide](Documentation/ShellStyleGuide.md) before writing or reviewing
scripts.


## Formatting and linting

  - `Tools/format` formats Markdown with rumdl, in place.
  - `Tools/lint` checks it. Configuration is in `.rumdl.toml` (100-character lines).
  - `Tools/install-git-hooks` installs a pre-push hook that runs `Tools/lint`.

Run `Tools/lint` before considering a change done.
