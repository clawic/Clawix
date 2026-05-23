import SwiftUI

/// Overlay shown over the in-app browser while the user is annotating: a
/// status pill at the top, and a centered comment editor once an element has
/// been clicked. Observes the tab controller so it tracks annotation state
/// without the parent view having to.
struct BrowserAnnotationOverlay: View {
    @ObservedObject var controller: BrowserTabController

    var body: some View {
        ZStack {
            if controller.annotating, controller.pendingAnnotationDraft == nil {
                AnnotatingPill()
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            if let draft = controller.pendingAnnotationDraft {
                CommentEditor(
                    marker: draft.marker,
                    elementLabel: draft.elementLabel,
                    onSubmit: { controller.submitAnnotation(comment: $0) },
                    onCancel: { controller.cancelAnnotationDraft() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.16), value: controller.annotating)
        .animation(.easeOut(duration: 0.16), value: controller.pendingAnnotationDraft)
    }
}

private struct AnnotatingPill: View {
    var body: some View {
        HStack(spacing: 7) {
            LucideIcon.auto("bubble.left", size: 12)
                .foregroundColor(Color(red: 0.45, green: 0.62, blue: 0.98))
            Text("Annotating")
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(Color(white: 0.95))
            Text("Click an element to comment")
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Color(white: 0.60))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
    }
}

private struct CommentEditor: View {
    let marker: Int
    let elementLabel: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text("\(marker)")
                        .font(BodyFont.system(size: 11, wght: 700))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(red: 0.23, green: 0.51, blue: 0.96)))
                    Text(headerText)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Color(white: 0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 11)

                TextField("Add a comment…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .lineLimit(1...4)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(white: 0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                    )
                    .padding(.horizontal, 16)
                    .onSubmit(submit)

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(SheetCancelButtonStyle())
                    Button("Add") { submit() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(SheetPrimaryButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 14)
            }
            .frame(width: 420)
            .sheetStandardBackground()
        }
        .onAppear { focused = true }
    }

    private var headerText: String {
        let label = elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Add a comment" : "Comment on \(label)"
    }

    private func submit() {
        onSubmit(text)
    }
}
