# Paste Again

A small clipboard history for the macOS menu bar. It records the plain text you copy, and
`⌘⇧V` opens a search panel over that history. Pick an entry with the arrow keys and press
`Enter` to paste it into the app you were just using.

- Text only: no images, files or rich text.
- Keeps the last 1,000 entries in a local file. No network, no accounts, no sync.
- Skips anything that password managers mark as concealed or transient
  ([nspasteboard.org](http://nspasteboard.org) convention).
- Paste-back needs the Accessibility permission. Recording and search work without it.
- English, German, French, Spanish and Italian.

## Building

```sh
swift build                    # compile check
./script/build_and_run.sh      # build an app bundle into dist/ and launch it
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
Run `xcodegen generate` after editing it. To sign with your own account, replace
`DEVELOPMENT_TEAM` in `project.yml` and `teamID` in `Configuration/ExportOptions.plist`.

Tests run with `swift test` or from Xcode. They need a full Xcode install, not just the
Command Line Tools.

## License

MIT, see [LICENSE](LICENSE).
