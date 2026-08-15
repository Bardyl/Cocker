# Contributing

Thanks for looking. Cocker is small on purpose, and the goal is to keep it that way.

## Getting set up

```sh
git clone https://github.com/Bardyl/Cocker.git
cd Cocker
swift test          # should pass without Docker installed
./Scripts/bundle.sh && open build/Cocker.app
```

You need Xcode 16 or later. You do **not** need Docker or colima to build or to run
the tests — the parsers are tested against captured CLI output, on purpose.

## Where things live

| Path | What it holds |
|---|---|
| `Sources/Cocker/Core/` | Everything that talks to `brew`, `colima` and `docker` |
| `Sources/Cocker/State/` | `AppState` — polling, actions, error handling |
| `Sources/Cocker/UI/` | SwiftUI views, and `DogTalk.swift` for all user-facing wording |
| `Tests/CockerTests/` | Parser tests |
| `Scripts/` | Bundling and icon generation |

Read [`docs/architecture.md`](docs/architecture.md) first. It explains why Cocker
shells out to CLIs rather than using the Docker API, and lists what it deliberately
refuses to do. A pull request that crosses one of those lines needs to argue the case.

## Things worth knowing

**Parsing external output is the fragile part.** `colima status --json` and
`colima list --json` do not even agree with each other on key names. Any change to
how CLI output is read must come with a test using real captured output — that is
what `Tests/CockerTests/ParsingTests.swift` is for.

**A GUI process has no useful `PATH`.** Everything goes through `Shell.run`, which
rebuilds one. Never call a tool by bare name.

**Errors keep their original text.** The interface is playful; failure messages are
not. Whatever the command printed gets shown verbatim, next to whatever friendly
title wraps it. Debugging a joke is miserable.

## Language

- Code comments are in French, matching the rest of the codebase.
- Commit messages, issues, pull requests and documentation are in English.
- The interface ships in English and French. English strings in the source are
  the translation keys; French lives in `Resources/fr.lproj/Localizable.strings`.
  `Scripts/check-translations.py` fails the build if a visible string has no
  French counterpart, and CI runs it.
- Adding a language means a new `.lproj` beside the others plus an entry in
  `AppLanguage`. `DogTalk.swift` holds the dog wording: rewrite the tone, do not
  translate it literally — the jokes do not survive a word-for-word pass.

**Watch out for `Text`.** `Text("a literal")` is a `LocalizedStringKey` and gets
translated; `Text(someVariable)` takes the `StringProtocol` overload and is shown
as-is. Model layer labels are variables, so they go through `Text(key:)`. For
strings composed before display, use `localized(_:_:)` with the environment
locale.

## Commits

Describe the effect, not the gesture: *fix path re-reading* rather than *modify
ProjectStore*. Explain **why** in the body; the diff already says what. One intent
per commit — a formatting pass and a behaviour change do not travel together.

## Before opening a pull request

- `swift test` passes.
- `swift build` produces no warnings.
- You have actually run the app, not only compiled it. Several bugs in this project
  looked fine in the code and only showed up on screen.
