# Repository instructions

## Local verification

- Do not run local full-application builds, including `xcodebuild build`,
  `xcodebuild archive`, or repository scripts that build/package the macOS app,
  unless the user explicitly requests a local build.
- Do not use a local full-app build as a routine pre-commit check. Full Debug
  and Release builds are verified by GitHub Actions.
- Prefer lightweight, targeted tests, smoke checks, linting, and static
  validation that do not build the complete application.
