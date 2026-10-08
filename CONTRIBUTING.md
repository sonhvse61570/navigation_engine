# Contributing

This is a Dart workspace: one repo, several packages under `packages/`, resolved together from the root `pubspec.yaml`.

## Setup

You need a recent stable Flutter SDK (`navigation_engine_google_maps` needs Flutter 3.47 or newer).

```sh
flutter pub get   # at the repo root, resolves every package
```

The `example/` apps are not part of the workspace; run `flutter pub get` inside an example before running it. The Google Maps and Mapbox examples need your own keys, see the README of each package.

## Before you open a PR

Run these from the repo root:

```sh
dart format packages
for p in packages/*/; do (cd "$p" && flutter analyze && flutter test); done
tool/import_all_check.sh # every package in one app, no clash (after pub get)
```

CI runs the same checks. Also:

- Add or update tests for the change.
- Add a line to the `CHANGELOG.md` of each touched package.
- Never commit API keys or tokens. `local.properties` and `Secrets.xcconfig` are gitignored for that reason.

## Commit messages

Short imperative subject, for example `Fix snapping near U-turns`. Explain the why in the body when it is not obvious.
