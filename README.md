# Kanvas (仮名)

Kanban-first task management for macOS.

## Install

Homebrew (cask):

```sh
brew install --cask s-age/kanvas/kanvas
```

## Build from source

Requires the Swift 6 toolchain and macOS 15+.

```sh
swift build                 # build
swift test                  # run tests
./Scripts/build.sh --install  # assemble Kanvas.app and install to /Applications
```

## Release

```sh
./Scripts/release.sh        # signed, notarized, stapled Kanvas-<version>.dmg
```
