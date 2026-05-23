import SwiftUI
import AppKit
import Foundation
import os

/// Categories the report can be filed under. Kept short and neutral so
/// the chip row reads cleanly.
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case praise
    case issue
    case bug
    case safety
    case other

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .praise: return "Praise"
        case .issue:  return "Issue"
        case .bug:    return "Bug"
        case .safety: return "Safety"
        case .other:  return "Other"
        }
    }
}

/// Root overlay that dims the window and centers the feedback card.
/// Mirrors `CommandPaletteOverlay` so the app keeps one presentation
/// language for centered modals.
struct FeedbackOverlay: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            if appState.isFeedbackOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { appState.isFeedbackOpen = false }
                    .transition(.opacity)

                FeedbackDialogView(isPresented: Binding(
                    get: { appState.isFeedbackOpen },
                    set: { appState.isFeedbackOpen = $0 }
                ))
                .frame(width: 460)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeOut(duration: 0.18), value: appState.isFeedbackOpen)
        .ignoresSafeArea()
    }
}

/// The feedback form. Two phases: composing → sent. On send it writes a
/// local report bundle into the diagnostics directory and surfaces its
/// id. The saved report is redacted by default and references local
/// diagnostic artifacts by file name only, so a later agent has useful
/// evidence without inheriting prompts, secrets, or full local paths.
struct FeedbackDialogView: View {
    @Binding var isPresented: Bool

    @State private var category: FeedbackCategory = .praise
    @State private var message: String = ""
    @State private var includeDiagnostics = true
    @State private var savedReceipt: FeedbackReceipt?
    @State private var saveError: String?

    private var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let receipt = savedReceipt {
                sentPhase(receipt)
            } else {
                composePhase
            }
        }
        .padding(20)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.28)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 36, y: 18)
        .background(
            Button("", action: { isPresented = false })
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    // MARK: Compose

    private var composePhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send feedback")
                .font(BodyFont.system(size: 16, wght: 600))
                .foregroundColor(Palette.textPrimary)

            categoryRow

            ZStack(alignment: .topLeading) {
                if trimmed.isEmpty {
                    Text("What worked, what didn't, what you expected")
                        .font(BodyFont.system(size: 13))
                        .foregroundColor(Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .font(BodyFont.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(height: 120)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            Toggle(isOn: $includeDiagnostics) {
                Text("Include recent diagnostics")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Palette.pastelBlue)

            if let saveError {
                Text(verbatim: saveError)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Color.red.opacity(0.85))
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                FeedbackButton(title: "Cancel", style: .secondary) {
                    isPresented = false
                }
                FeedbackButton(title: "Send", style: .primary, disabled: trimmed.isEmpty) {
                    submit()
                }
            }
        }
    }

    private var categoryRow: some View {
        HStack(spacing: 6) {
            ForEach(FeedbackCategory.allCases) { cat in
                let selected = cat == category
                Button {
                    category = cat
                } label: {
                    Text(cat.label)
                        .font(BodyFont.system(size: 12, wght: selected ? 600 : 500))
                        .foregroundColor(selected ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(selected ? 0.12 : 0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.12), value: category)
    }

    // MARK: Sent

    private func sentPhase(_ receipt: FeedbackReceipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thanks for the feedback")
                .font(BodyFont.system(size: 16, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Saved as report \(receipt.id). Reveal it to attach the bundle to a report whenever you like.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                FeedbackButton(title: "Reveal", style: .secondary) {
                    NSWorkspace.shared.activateFileViewerSelecting([receipt.url])
                }
                FeedbackButton(title: "Done", style: .primary) {
                    isPresented = false
                }
            }
        }
    }

    private func submit() {
        do {
            savedReceipt = try FeedbackWriter.write(
                category: category,
                message: trimmed,
                includeDiagnostics: includeDiagnostics
            )
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Local report writer

struct FeedbackReceipt {
    let id: String
    let url: URL
}

enum FeedbackWriter {
    struct Report: Codable, Equatable {
        struct Message: Codable, Equatable {
            var redactedText: String
            var originalCharacterCount: Int
            var redactionApplied: Bool
        }

        struct App: Codable, Equatable {
            var version: String
            var build: String
            var os: String
        }

        struct Diagnostics: Codable, Equatable {
            var included: Bool
            var directoryName: String
            var artifacts: [DiagnosticArtifactReference]
        }

        struct Redaction: Codable, Equatable {
            var privacy: String
            var promptsIncluded: Bool
            var secretsIncluded: Bool
            var fullLocalPathsIncluded: Bool
            var externalSubmission: String
        }

        struct AgentHandoff: Codable, Equatable {
            var summary: String
            var nextSteps: [String]
            var evidenceCategories: [String]
            var performanceTaxonomyCategories: [String]
        }

        var schemaVersion: Int
        var id: String
        var category: String
        var createdAt: String
        var message: Message
        var app: App
        var diagnostics: Diagnostics
        var redaction: Redaction
        var agentHandoff: AgentHandoff
    }

    static func write(
        category: FeedbackCategory,
        message: String,
        includeDiagnostics: Bool,
        applicationSupportRoot: URL? = nil,
        bundleIdentifier: String = ClawixDiagnosticStorageRoutes.bundleIdentifier(),
        now: Date = Date(),
        fileManager fm: FileManager = .default
    ) throws -> FeedbackReceipt {
        let log = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.example.clawix",
            category: ClawixDiagnosticLogCategory.export
        )
        guard let root = applicationSupportRoot ?? ClawixDiagnosticStorageRoutes.applicationSupportRoot(fileManager: fm) else {
            throw NSError(domain: "Feedback", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not locate Application Support."
            ])
        }

        let shortId = String(UUID().uuidString.prefix(8))
        let diagnosticsDir = ClawixDiagnosticStorageRoutes
            .diagnosticsDirectoryURL(applicationSupportRoot: root, bundleIdentifier: bundleIdentifier)
        let reportDir = diagnosticsDir
            .appendingPathComponent("feedback", isDirectory: true)
            .appendingPathComponent("feedback-\(shortId)", isDirectory: true)
        try fm.createDirectory(at: reportDir, withIntermediateDirectories: true)

        if includeDiagnostics,
           applicationSupportRoot == nil {
            ResourceSampler.sampleNowAndPersist()
        }

        let artifacts = includeDiagnostics
            ? DiagnosticArtifactClassifier.collectRecentReferences(in: diagnosticsDir, fileManager: fm)
            : []
        let redactedMessage = ClawixDiagnosticRedactor.redact(message)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let evidenceCategories = DiagnosticArtifactClassifier.categories(
            from: message,
            artifacts: artifacts
        )
        let performanceCategories = evidenceCategories.filter { category in
            DiagnosticEvidenceCategory.performanceTaxonomyRawValues.contains(category)
        }
        let payload = Report(
            schemaVersion: 1,
            id: shortId,
            category: category.rawValue,
            createdAt: ISO8601DateFormatter().string(from: now),
            message: Report.Message(
                redactedText: redactedMessage,
                originalCharacterCount: message.count,
                redactionApplied: redactedMessage != message
            ),
            app: Report.App(
                version: appVersion,
                build: build,
                os: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            diagnostics: Report.Diagnostics(
                included: includeDiagnostics,
                directoryName: ClawixDiagnosticStorageRoutes.diagnosticsDirectoryName,
                artifacts: artifacts
            ),
            redaction: Report.Redaction(
                privacy: "redacted",
                promptsIncluded: false,
                secretsIncluded: false,
                fullLocalPathsIncluded: false,
                externalSubmission: "explicit_approval_only"
            ),
            agentHandoff: Report.AgentHandoff(
                summary: "User-submitted local feedback report with redacted message and diagnostic artifact references.",
                nextSteps: [
                    "Open the referenced local diagnostics directory on the user's machine if more detail is needed.",
                    "Use evidenceCategories and performanceTaxonomyCategories to choose the first subsystem to inspect.",
                    "Ask for explicit approval before sharing diagnostics outside the machine."
                ],
                evidenceCategories: evidenceCategories,
                performanceTaxonomyCategories: performanceCategories
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let url = reportDir.appendingPathComponent("report.json", isDirectory: false)
        try data.write(to: url, options: .atomic)
        PerfSignpost.diagnosticsExport.event("feedback.artifacts", artifacts.count)
        log.info("feedback report \(shortId, privacy: .public) saved with \(artifacts.count, privacy: .public) diagnostic references")
        return FeedbackReceipt(id: shortId, url: reportDir)
    }
}

// MARK: - Button

private struct FeedbackButton: View {
    enum Style { case primary, secondary }
    let title: LocalizedStringKey
    var style: Style
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(foreground)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule(style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        switch style {
        case .primary:   return Color(white: 0.08)
        case .secondary: return Palette.textPrimary
        }
    }

    private var fill: Color {
        switch style {
        case .primary:   return Color(white: hovering ? 1.0 : 0.94)
        case .secondary: return Color.white.opacity(hovering ? 0.14 : 0.10)
        }
    }
}
