import SwiftUI

/// Personalization sub-card that toggles the sentinel-delimited "Secrets
/// (Clawix)" block in `~/.codex/AGENTS.md`. When the toggle is on, the
/// block is written to AGENTS.md (preserving everything else); when off,
/// the block is removed cleanly (sentinel + body + surrounding blank).
struct SecretsCodexInjectionCard: View {
    @State private var isInjected: Bool = false
    @State private var body_: String = CodexSecretsBlock.defaultBody
    @State private var savedBody: String = CodexSecretsBlock.defaultBody
    @State private var error: String?
    @State private var didLoad = false
    @State private var isWorking = false

    private var isDirty: Bool { isInjected && body_ != savedBody }
    private var canMutate: Bool { didLoad && !isWorking }
    private var canSave: Bool { canMutate && isDirty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Secrets → Codex")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Inject a paragraph into ~/.codex/AGENTS.md teaching Codex how to use `claw secrets`. The block is delimited by sentinel comments so flipping the toggle off removes only this block, leaving the rest of your AGENTS.md untouched.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { isInjected },
                    set: { newValue in
                        guard canMutate else { return }
                        toggle(newValue: newValue)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!canMutate)
                .accessibilityLabel(Text("Secrets Codex injection"))
                .accessibilityHint(Text("Writes or removes the Secrets block in AGENTS.md."))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInjected ? "Codex injection is on" : "Codex injection is off")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(isInjected
                         ? "Codex sees the secrets paragraph at the top of every conversation."
                         : "Turn on to teach Codex how to call `claw secrets`.")
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if isInjected {
                    Button { resetToDefault() } label: {
                        Text("Reset to default")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.overlay(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMutate)
                }
            }
            .padding(.bottom, 14)

            if isInjected {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray(light: 0.96, dark: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.overlay(0.08), lineWidth: 0.5)
                        )
                    TextEditor(text: $body_)
                        .font(BodyFont.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .disabled(!canMutate)
                }
                .frame(height: 220)

                HStack(spacing: 10) {
                    if let error {
                        HStack(spacing: 8) {
                            Text(error)
                                .font(BodyFont.system(size: 11, wght: 500))
                                .foregroundColor(Palette.danger)
                            if !didLoad {
                                Button("Retry") { load() }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                            }
                        }
                    } else if isDirty {
                        Text("Unsaved changes")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                    }
                    Spacer()
                    Button { saveBody() } label: {
                        Text("Save paragraph")
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(isDirty ? Palette.textPrimary : Palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.overlay(isDirty ? 0.12 : 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
                .padding(.top, 10)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard !didLoad, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if let body = try CodexInstructionsFile.sentinelBlockBody(id: CodexSecretsBlock.id) {
                self.isInjected = true
                self.body_ = body
                self.savedBody = body
            } else {
                self.isInjected = false
                self.body_ = CodexSecretsBlock.defaultBody
                self.savedBody = CodexSecretsBlock.defaultBody
            }
            self.error = nil
            didLoad = true
        } catch {
            self.error = Self.failureMessage(for: error, surface: "secrets.codexInjection.load")
            didLoad = false
        }
    }

    private func toggle(newValue: Bool) {
        guard canMutate else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if newValue {
                let bodyToWrite = body_.isEmpty ? CodexSecretsBlock.defaultBody : body_
                try CodexInstructionsFile.replaceSentinelBlock(id: CodexSecretsBlock.id, body: bodyToWrite)
                self.body_ = bodyToWrite
                self.savedBody = bodyToWrite
                self.isInjected = true
            } else {
                try CodexInstructionsFile.removeSentinelBlock(id: CodexSecretsBlock.id)
                self.isInjected = false
            }
            self.error = nil
        } catch {
            self.error = Self.failureMessage(for: error, surface: "secrets.codexInjection.toggle")
        }
    }

    private func saveBody() {
        guard canSave else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try CodexInstructionsFile.replaceSentinelBlock(id: CodexSecretsBlock.id, body: body_)
            savedBody = body_
            error = nil
        } catch {
            self.error = Self.failureMessage(for: error, surface: "secrets.codexInjection.save")
        }
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: rawMessage, surface: surface)
    }

    private func resetToDefault() {
        body_ = CodexSecretsBlock.defaultBody
        if isInjected {
            saveBody()
        }
    }
}
