import SwiftUI

/// Signed-out screen. Authentication is via a **Personal Access Token (classic)** the user
/// pastes in — this avoids the OAuth per-organization grant screen while keeping full access.
struct LoginView: View {
    @Bindable var store: AppStore
    @State private var tokenInput = ""

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("r2-git2").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text("Your GitHub PRs & Actions, in the menu bar")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            tokenEntry

            if let error = store.lastError {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.failure)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var tokenEntry: some View {
        VStack(spacing: 10) {
            Text("Sign in with a classic personal access token (scopes: repo, read:org, notifications).")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                openInBrowser(Config.tokenCreationURL)
            } label: {
                Label("Create a token on GitHub", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11.5, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Theme.textPrimary)
            .help("Opens GitHub with the required scopes pre-selected")

            SecureField("ghp_…", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(submitToken)

            Button(action: submitToken) {
                HStack(spacing: 6) {
                    if store.isValidatingToken { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    Text(store.isValidatingToken ? "Validating…" : "Save token")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Theme.accent.opacity(tokenInput.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
            .disabled(tokenInput.isEmpty || store.isValidatingToken)
        }
    }

    private func submitToken() {
        let token = tokenInput
        guard !token.isEmpty, !store.isValidatingToken else { return }
        Task { await store.signIn(withToken: token); tokenInput = "" }
    }
}
