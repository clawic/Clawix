import SwiftUI

struct BrowserUsagePage: View {
    @AppStorage(BrowserPermissionPolicy.approvalStorageKey) private var approval: String = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue
    @AppStorage(BrowserPermissionPolicy.agentControlEnabledKey) private var agentControlEnabled = true
    @AppStorage(BrowserPermissionPolicy.annotationScreenshotsKey) private var annotationScreenshots = true
    @State private var browserStorage: BrowserPermissionPolicy.BrowserStorageKind = .all
    @State private var clearStatus: String?
    @State private var clearingBrowsingData = false
    @State private var blockedDomains: [String] = []
    @State private var allowedDomains: [String] = []

    private var browserStorageOptions: [(BrowserPermissionPolicy.BrowserStorageKind, String)] {
        [
            (.all, L10n.t("Clear all browsing data")),
            (.cache, L10n.t("Clear cache")),
            (.cookies, L10n.t("Clear cookies"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Browser usage")

            SectionLabel(title: "Browser Use")
            SettingsCard {
                ToggleRow(
                    title: "Let the agent control the built-in browser",
                    detail: "Allow the agent to open pages, navigate, and read the in-app browser while it works.",
                    isOn: $agentControlEnabled
                )
                CardDivider()
                ToggleRow(
                    title: "Annotation screenshots",
                    detail: "Attach a page screenshot with each annotation you send so the agent sees exactly what you mean.",
                    isOn: $annotationScreenshots
                )
            }
            .padding(.bottom, 28)

            SectionLabel(title: "Browser")
            SettingsCard {
                SettingsRow {
                    RowLabel(
                        title: "Browsing data",
                        detail: "Clear site data and the cache of the in-app browser"
                    )
                } trailing: {
                    HStack(spacing: 8) {
                        SettingsDropdown(
                            options: browserStorageOptions,
                            selection: $browserStorage,
                            minWidth: 190
                        )
                        .disabled(clearingBrowsingData)
                        Button {
                            clearSelectedBrowserStorage()
                        } label: {
                            HStack(spacing: 5) {
                                if clearingBrowsingData {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 11, height: 11)
                                }
                                Text(clearingBrowsingData ? L10n.t("Clearing…") : L10n.t("Clear"))
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(clearingBrowsingData ? Palette.textSecondary : Palette.textPrimary)
                        .disabled(clearingBrowsingData)
                        .accessibilityLabel(Text("Clear browsing data"))
                        .accessibilityHint(Text("Clears the selected persisted browser data from the in-app browser."))
                    }
                }
                .liftWhenSettingsDropdownOpen()
            }
            if let clearStatus {
                InfoBanner(text: clearStatus, kind: .ok)
                    .padding(.top, 10)
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                DropdownRow(
                    title: "Approval",
                    detail: "Choose whether Clawix asks for permission before opening websites",
                    options: [
                        (BrowserPermissionPolicy.Approval.alwaysAsk.rawValue, "Always ask"),
                        (BrowserPermissionPolicy.Approval.alwaysAllow.rawValue, "Always allow"),
                        (BrowserPermissionPolicy.Approval.alwaysBlock.rawValue, "Always block")
                    ],
                    selection: $approval
                )
                CardDivider()
                BrowserPolicyStatusRow(
                    title: "History",
                    detail: "Unavailable until a browser-history route consumes this policy and reports approval state.",
                    status: "Blocked"
                )
            }

            DomainListSection(title: "Blocked domains",
                              subtitle: "Clawix will never open these sites",
                              emptyText: "No blocked domains",
                              domains: $blockedDomains,
                              list: .blocked,
                              onChanged: reloadDomains)
                .padding(.top, 28)

            DomainListSection(title: "Allowed domains",
                              subtitle: "Domains that open without prompting",
                              emptyText: "No allowed domains",
                              domains: $allowedDomains,
                              list: .allowed,
                              onChanged: reloadDomains)
                .padding(.top, 28)
        }
        .onAppear {
            normalizeBrowserPermissionValues()
            reloadDomains()
        }
    }

    private func normalizeBrowserPermissionValues() {
        let valid = [
            BrowserPermissionPolicy.Approval.alwaysAsk.rawValue,
            BrowserPermissionPolicy.Approval.alwaysAllow.rawValue,
            BrowserPermissionPolicy.Approval.alwaysBlock.rawValue,
        ]
        if !valid.contains(approval) { approval = BrowserPermissionPolicy.Approval.alwaysAsk.rawValue }
    }

    private func reloadDomains() {
        blockedDomains = BrowserPermissionPolicy.blockedDomains
        allowedDomains = BrowserPermissionPolicy.allowedDomains
    }

    private func clearSelectedBrowserStorage() {
        guard !clearingBrowsingData else { return }
        clearingBrowsingData = true
        clearStatus = nil
        let selected = browserStorage
        BrowserPermissionPolicy.clearBrowserStorage(selected) {
            clearingBrowsingData = false
            clearStatus = String(
                format: L10n.t("WebKit reported completion for %@. Settings does not receive per-site deletion counts."),
                locale: AppLocale.current,
                selected.statusLabel
            )
            ToastCenter.shared.show(clearStatus ?? L10n.t("Browser storage clear completed."))
        }
    }
}

private extension BrowserPermissionPolicy.BrowserStorageKind {
    var statusLabel: String {
        switch self {
        case .all:
            return L10n.t("all browsing data")
        case .cache:
            return L10n.t("cache")
        case .cookies:
            return L10n.t("cookies")
        }
    }
}

private struct BrowserPolicyStatusRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            Text(status)
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .accessibilityLabel(Text(status))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct DomainListSection: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let emptyText: LocalizedStringKey
    @Binding var domains: [String]
    let list: BrowserPermissionPolicy.DomainList
    let onChanged: () -> Void

    @State private var draft = ""
    @State private var error: String?
    @State private var isMutating = false

    private var canAddDomain: Bool {
        !isMutating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button {
                    addDomain()
                } label: {
                    HStack(spacing: 5) {
                        if isMutating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 11, height: 11)
                        } else {
                            LucideIcon(.plus, size: 11)
                        }
                        Text("Add")
                            .font(BodyFont.system(size: 12, wght: 600))
                    }
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.overlay(0.08))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.overlay(0.10), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAddDomain)
                .accessibilityLabel(Text("Add browser domain"))
                .accessibilityHint(Text("Adds the domain to this persisted browser permission list."))
            }
            Text(subtitle)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("example.com", text: $draft)
                        .textFieldStyle(.plain)
                        .font(BodyFont.system(size: 12.5))
                        .foregroundColor(Palette.textPrimary)
                        .disabled(isMutating)
                        .onSubmit(addDomain)
                    Button("Add") {
                        addDomain()
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .disabled(!canAddDomain)
                    .accessibilityLabel(Text("Add browser domain"))
                    .accessibilityHint(Text("Adds the domain to this persisted browser permission list."))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let error {
                    CardDivider()
                    InfoBanner(text: error, kind: .error)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                if domains.isEmpty {
                    CardDivider()
                    HStack {
                        Spacer()
                        Text(emptyText)
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 18)
                } else {
                    ForEach(domains, id: \.self) { domain in
                        CardDivider()
                        HStack(spacing: 10) {
                            Text(verbatim: domain)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer()
                            Button("Remove") {
                                removeDomain(domain)
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                            .disabled(isMutating)
                            .accessibilityLabel(Text(String(format: L10n.t("Remove %@ from browser permissions"), locale: AppLocale.current, domain)))
                            .accessibilityHint(Text("Removes the domain from this persisted browser permission list."))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray(light: 0.95, dark: 0.085))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.overlay(0.10), lineWidth: 0.5)
                    )
            )
        }
    }

    private func addDomain() {
        guard canAddDomain else { return }
        isMutating = true
        defer { isMutating = false }
        guard let domain = BrowserPermissionPolicy.addDomain(draft, to: list) else {
            error = L10n.t("Enter a valid domain such as example.com.")
            return
        }
        error = nil
        draft = ""
        reloadFromPolicy()
        onChanged()
        ToastCenter.shared.show(String(format: L10n.t("Added %@"), locale: AppLocale.current, domain))
    }

    private func removeDomain(_ domain: String) {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        BrowserPermissionPolicy.removeDomain(domain, from: list)
        error = nil
        reloadFromPolicy()
        onChanged()
    }

    private func reloadFromPolicy() {
        switch list {
        case .blocked:
            domains = BrowserPermissionPolicy.blockedDomains
        case .allowed:
            domains = BrowserPermissionPolicy.allowedDomains
        }
    }
}
