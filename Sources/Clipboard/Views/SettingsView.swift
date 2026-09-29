import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Open History") {
                    HStack(spacing: 8) {
                        shortcutField

                        Button(recordingButtonTitle) {
                            if viewModel.isRecording {
                                viewModel.cancelRecording()
                            } else {
                                viewModel.beginRecording()
                            }
                        }

                        Button("Reset") {
                            viewModel.resetToDefault()
                        }
                        .disabled(viewModel.shortcut == .default && !viewModel.isRecording)
                    }
                }

                Text(hintText)
                    .font(.callout)
                    .foregroundStyle(viewModel.validationMessage == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("General") {
                Toggle("Start \(AppConstants.appName) at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)

                Text(viewModel.launchAtLoginMessage ?? defaultLaunchAtLoginHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.appName)
                        .font(.headline)

                    Text("Searchable local clipboard history for macOS.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(viewModel.appVersionDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let websiteURL = URL(string: viewModel.websiteURLString) {
                        Link(destination: websiteURL) {
                            Label(viewModel.websiteURLString, systemImage: "safari")
                        }
                        .padding(.top, 2)
                    }

                    if let privacyPolicyURL = URL(string: viewModel.privacyPolicyURLString) {
                        Link(destination: privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .frame(
            width: AppConstants.settingsWindowWidth,
            height: AppConstants.settingsWindowHeight
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    /// Declared as `LocalizedStringKey` so both branches are looked up rather than
    /// resolving to the plain-`String` overload of `Button`.
    private var recordingButtonTitle: LocalizedStringKey {
        viewModel.isRecording ? "Cancel" : "Assign"
    }

    private var defaultLaunchAtLoginHint: String {
        String(localized: "Off by default. \(AppConstants.appName) only adds itself to your login items while this is checked.")
    }

    private var shortcutField: some View {
        // The shortcut itself is a key combination, not translatable text, so both branches
        // go through the plain-`String` overload of `Text`.
        Text(viewModel.isRecording ? String(localized: "Press keys…") : viewModel.shortcut.displayString)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(viewModel.isRecording ? Color.secondary : Color.primary)
            .frame(minWidth: 92, minHeight: 22)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        viewModel.isRecording ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: viewModel.isRecording ? 2 : 1
                    )
            )
    }

    private var hintText: String {
        if let validationMessage = viewModel.validationMessage {
            return validationMessage
        }

        if viewModel.isRecording {
            return String(localized: "Recording — press the new key combination, or ⎋ to cancel.")
        }

        return String(localized: "Press Assign, then type the key combination that should open the clipboard history.")
    }
}
