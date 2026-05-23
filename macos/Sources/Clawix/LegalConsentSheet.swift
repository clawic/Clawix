import SwiftUI

struct LegalConsentGate: View {
    @ObservedObject var legal: LegalSafetyStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(
                isPresented: Binding(
                    get: { !legal.hasAcceptedCurrentLegal },
                    set: { _ in }
                )
            ) {
                LegalConsentSheet(legal: legal)
                    .interactiveDismissDisabled(true)
            }
    }
}

struct LegalConsentSheet: View {
    @ObservedObject var legal: LegalSafetyStore
    @State private var adultConfirmed = false
    @State private var acceptedDocuments = false

    private var canAccept: Bool {
        adultConfirmed && acceptedDocuments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review legal and safety terms")
                .font(BodyFont.system(size: 20, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 8)

            Text("Clawix is local-first and assistive. It is not an emergency service and does not provide professional medical, mental health, legal, financial, insurance, employment, education, government, or physical-safety decisions.")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                LegalConsentToggle(isOn: $adultConfirmed, text: "I confirm I am at least 18 years old.")
                LegalConsentToggle(isOn: $acceptedDocuments, text: "I accept the Terms, Privacy Notice, Disclaimer, Safety Policy, Regulated Domains policy, and EULA version 2026-05-18.")
            }
            .padding(.bottom, 18)

            InfoBanner(
                text: LegalSafetyPolicy.crisisDisclaimer,
                kind: .danger
            )
            .padding(.bottom, 18)

            HStack {
                Spacer()
                Button("Accept and continue") {
                    legal.acceptCurrentLegal(adultConfirmed: adultConfirmed)
                }
                .buttonStyle(SheetPrimaryButtonStyle())
                .disabled(!canAccept)
                .opacity(canAccept ? 1 : 0.45)
            }
        }
        .padding(24)
        .frame(width: 560)
        .sheetStandardBackground()
    }
}

private struct LegalConsentToggle: View {
    @Binding var isOn: Bool
    let text: LocalizedStringKey

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? Color(red: 0.30, green: 0.55, blue: 1.0) : Color.overlay(0.08))
                        .frame(width: 18, height: 18)
                    if isOn {
                        LucideIcon(.check, size: 12)
                            .foregroundColor(Palette.textPrimary)
                    }
                }
                Text(text)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}
