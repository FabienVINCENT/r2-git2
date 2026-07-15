import SwiftUI

/// First-run / signed-out screen. Drives the OAuth Device Flow: shows the user code, offers to
/// copy it and open github.com/login/device, and reflects polling status.
struct LoginView: View {
    @Bindable var store: AppStore
    @State private var copied = false

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

            if !Config.isClientIDConfigured {
                notConfigured
            } else if let code = store.deviceCode {
                deviceFlow(code)
            } else {
                signInPrompt
            }

            if let error = store.lastError {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.failure)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - States

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Text("Sign in with your GitHub account to get started.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { store.startSignIn() } label: {
                Text("Sign in with GitHub")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
        }
    }

    private func deviceFlow(_ code: DeviceFlowAuth.DeviceCode) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub:")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)

            Text(code.userCode)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents(); pb.setString(code.userCode, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11.5, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Theme.textPrimary)

                Button {
                    openInBrowser(code.verificationURI)
                } label: {
                    Label("Open GitHub", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11.5, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(store.deviceFlowStatus ?? "Waiting for authorization…")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
            }

            Button("Cancel") { store.cancelSignIn() }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
    }

    private var notConfigured: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver").foregroundStyle(Theme.pending)
            Text("Setup required")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Set `GITHUB_CLIENT_ID` in Config.swift with your OAuth App's Client ID, then rebuild. See the README.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
    }
}
