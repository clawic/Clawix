import SwiftUI

struct IOSLegalConsentSheet: View {
    @Bindable var legal: IOSLegalSafetyStore
    @State private var adultConfirmed = false
    @State private var acceptedDocuments = false

    private var canAccept: Bool {
        adultConfirmed && acceptedDocuments
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.t("Clawix is local-first and assistive. It is not an emergency service and does not provide professional medical, mental health, legal, financial, insurance, employment, education, government, or physical-safety decisions."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L10n.t("I confirm I am at least 18 years old."), isOn: $adultConfirmed)
                    .font(.subheadline.weight(.semibold))

                Toggle(L10n.t("I accept the Terms, Privacy Notice, Disclaimer, Safety Policy, Regulated Domains policy, and EULA version 2026-05-18."), isOn: $acceptedDocuments)
                    .font(.subheadline.weight(.semibold))

                Text(L10n.t("In an emergency or crisis, contact local emergency services or trusted local resources. Clawix is not an emergency service."))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button {
                    legal.acceptCurrentLegal(adultConfirmed: adultConfirmed)
                } label: {
                    Text(L10n.t("Accept and continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAccept)
            }
            .padding(20)
            .navigationTitle("Review legal and safety terms")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
