import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft: String = ""
    @State private var isKeyConfigured: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var alertItem: AlertItem?

    private struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var trimmedKey: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                connectionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { refreshKeyConfigured() }
            .confirmationDialog(
                "Remove the saved API key?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove key", role: .destructive) { clearKey() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(item: $alertItem) { item in
                Alert(title: Text(item.title), message: Text(item.message))
            }
        }
    }

    private var apiKeySection: some View {
        Section("Anthropic API key") {
            if isKeyConfigured {
                Label("Key configured", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.focusAccent)
            }

            SecureField("Paste your Anthropic API key", text: $keyDraft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button("Save key") { saveKey() }
                .disabled(trimmedKey.isEmpty)

            if isKeyConfigured {
                Button("Clear saved key", role: .destructive) {
                    showClearConfirmation = true
                }
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            Button {
                runTestConnection()
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    if isTestingConnection {
                        ProgressView()
                    }
                }
            }
            .disabled(!isKeyConfigured || isTestingConnection)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("FocusFrame uses claude-sonnet-4-5 to generate reflective insights. Your key is stored only in your device's keychain and is never logged.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshKeyConfigured() {
        isKeyConfigured = (try? state.keychainService.loadAPIKey()) != nil
    }

    private func saveKey() {
        do {
            try state.keychainService.saveAPIKey(trimmedKey)
            keyDraft = ""
            isKeyConfigured = true
            alertItem = AlertItem(title: "Key saved", message: "Your API key is now stored in the keychain.")
        } catch {
            alertItem = AlertItem(
                title: "Save failed",
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func clearKey() {
        do {
            try state.keychainService.deleteAPIKey()
            isKeyConfigured = false
            alertItem = AlertItem(title: "Key removed", message: "Your saved API key has been deleted.")
        } catch {
            alertItem = AlertItem(
                title: "Remove failed",
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func runTestConnection() {
        isTestingConnection = true
        Task {
            defer { isTestingConnection = false }
            do {
                try await state.claudeService.testConnection()
                alertItem = AlertItem(
                    title: "Connection works",
                    message: "Anthropic accepted your key and replied successfully."
                )
            } catch {
                alertItem = AlertItem(
                    title: "Connection failed",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }
}
