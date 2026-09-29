# AGENTS.md

## Project Overview

- Project name: `Clipboard`
- Type: macOS menu bar app
- Stack: SwiftPM, SwiftUI, AppKit interop, Carbon hotkey API, ServiceManagement
- Purpose: Record copied/cut plain text in the background and expose a searchable clipboard history with a configurable global shortcut (default `Cmd+Shift+V`).

## Workspace Conventions

- Keep the app menu-bar-only. Do not introduce a Dock-based main window unless explicitly requested.
- V1 is text-only. Do not add images, files, rich text, snippets, pinning, or sync unless the task explicitly asks for them.
- The settings window is intentionally small: shortcut assignment and About. Do not grow it without an explicit request.
- Use Context7 whenever possible and sensible to fetch current library, framework, SDK, API, or CLI documentation, especially when it can save time or reduce guesswork.
- Prefer small AppKit bridges over large imperative rewrites. SwiftUI remains the source of truth.
- Preserve the current product behavior:
  - clipboard polling in the background
  - persistent local history
  - global hotkey opens the history panel
  - `Enter` pastes into the previously active app
  - accessibility permission is required only for the paste-back action

## Important Paths

- App entry: `Sources/Clipboard/App/ClipboardApp.swift`
- App state/coordinator: `Sources/Clipboard/App/ClipboardAppModel.swift`
- Clipboard panel controller: `Sources/Clipboard/Services/ClipboardPanelController.swift`
- Panel UI: `Sources/Clipboard/Views/HistoryPanelView.swift`
- Settings UI: `Sources/Clipboard/Views/SettingsView.swift`
- Settings window bridge: `Sources/Clipboard/Services/SettingsWindowController.swift`
- Build/run script: `script/build_and_run.sh`
- App icon generator: `script/generate_app_icons.sh`
- Xcode project definition: `project.yml` (XcodeGen), bundle config in `Configuration/`

## Build And Run

- Preferred build check:
  - `swift build`
- `Clipboard.xcodeproj` is generated from `project.yml`. After editing `project.yml`, run:
  - `xcodegen generate`
- Preferred app launch:
  - `./script/build_and_run.sh`
- Verification launch:
  - `./script/build_and_run.sh --verify`
- After completing code changes, rebuild and restart the app so the running menu bar app uses the latest implementation.

## Releasing To The App Store

- Always build the upload package with:
  - `./script/archive_appstore.sh`
- Never archive or export for the App Store by hand. The script raises
  `CURRENT_PROJECT_VERSION` in `project.yml` before every build, and App Store Connect
  refuses an upload whose build number was already used. A manual archive reuses the
  number and the upload fails after the fact.
- The raised build number is a real source change. Commit `project.yml` together with the
  release.
- `MARKETING_VERSION` is the user-visible version and is *not* raised automatically. Change
  it deliberately when the release warrants it.
- Signing settings live in `project.yml` (`DEVELOPMENT_TEAM`) and
  `Configuration/ExportOptions.plist`. Both are checked in; there is nothing to configure
  per machine beyond being signed into the Apple ID in Xcode.

## Testing Notes

- There are test files under `Tests/ClipboardTests`.
- For every behavior-changing code change, follow TDD: write or update a focused test for the desired behavior first, run it and confirm it fails for the expected reason, then change production code.
- If the test cannot be run locally because of the toolchain or environment, report the exact blocker before implementation, then run the best available build or verify check after implementation.
- Add regression tests proactively whenever a change touches behavior that can reasonably break again, especially panel placement, mouse/keyboard interaction, paste-back, clipboard capture, persistence, permissions, launch-at-login, and search behavior.
- Always attempt to run the relevant tests after adding or changing behavior. If the local toolchain cannot run them, report the exact blocker and still run the best available build/verify check.
- In this environment, `swift test` may fail if only Command Line Tools are active and `XCTest` is unavailable.
- If full Xcode is active, prefer running the existing tests before changing behavior-heavy code.
- The XcodeGen unit-test target must keep `GENERATE_INFOPLIST_FILE = YES`; otherwise Xcode refuses to sign the test bundle because it has no `Info.plist`.
- In XcodeGen, app resources belong under the target's `sources` list so their file types are assigned to the Resources build phase; an unsupported top-level `resources` key is silently ignored.

## Architecture Notes

- `ClipboardStore` owns persistence and retention pruning.
- `ClipboardMonitorService` polls `NSPasteboard.general` and emits new text items.
- `GlobalHotkeyService` registers the system-wide hotkey through Carbon and re-registers when the shortcut changes.
- `HotkeyShortcut` models the Carbon key code/modifier pair, its display string, and the "needs ⌘/⌃/⌥" validity rule.
- `HotkeyPreferenceStore` persists the shortcut in `UserDefaults` and falls back to the default for missing or invalid values.
- `SettingsViewModel` owns shortcut recording state; `SettingsWindowController` hosts it in an `NSWindow` and forwards key events.
- `ClipboardPanelController` owns the `NSPanel`, focus behavior, app reactivation, and paste-back flow.
- `HistoryPanelViewModel` owns filtering, selection, and panel-local state.
- `LaunchAtLoginService` handles startup registration through `SMAppService.mainApp`.

## UI Notes

- The history panel must stay light in appearance. Keep the Alfred-style layout density, but do not switch the window back to a dark or black style unless explicitly requested.
- Maintain strong keyboard-first interaction. Arrow keys, `Enter`, and `Esc` are core behavior.
- Avoid bloating the menu bar menu. Use it for operational controls, not history browsing.

## Safety And Edge Cases

- Do not break the duplicate-suppression path used when the app pastes one of its own history items back into the system clipboard.
- Do not remove the previous-app handoff logic without replacing it with an equally reliable paste target strategy.
- Be careful with permission prompts. Clipboard recording should still work even if accessibility is denied.
- Login-item registration should fail gracefully. The app must remain usable even if macOS does not approve auto-start.
- Shortcut recording must run through the `SettingsWindow` subclass. SwiftUI `onKeyPress` and a plain focusable view never see modifier combinations such as `⌘X`, because those are dispatched as key equivalents; overriding `sendEvent` and `performKeyEquivalent` is the working fix.
- Reject shortcuts without `⌘`, `⌃`, or `⌥`. Carbon happily registers a shift-only hotkey, which then swallows ordinary typing system-wide.
- Do not re-register the login item on every launch or build. The debug app is ad-hoc signed, so repeated `SMAppService.mainApp.register()` calls can create duplicate System Settings entries.
- Sandboxed paste-back must post the synthetic shortcut through `CGEventSource(stateID: .combinedSessionState)` and `.cgAnnotatedSessionEventTap`. `postToPid` requires access to the target app's task port and silently fails from the App Sandbox even when Accessibility is granted.
- Give local sandbox test builds a distinct bundle ID and install them at a stable path before granting Accessibility. Reusing `com.nandersen.Clipboard` for both sandboxed and unsandboxed builds can make System Settings authorize the wrong app. Add the exact running test bundle manually with the `+` button when needed; after replacing an ad-hoc-signed test bundle, remove stale permission entries and re-add the installed bundle.

## Preferred Change Style

- Keep files focused by responsibility.
- Add comments only where the platform behavior is non-obvious.
- When implementation uncovers a repeatable technical hurdle, document the symptom and the working fix or workaround in this file before finishing, so the next agent does not rediscover it.
- When touching hotkey, panel, pasteboard, or activation logic, always do a build check afterward.
