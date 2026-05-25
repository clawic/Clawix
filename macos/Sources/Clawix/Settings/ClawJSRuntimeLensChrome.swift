import SwiftUI

struct ClawJSRuntimeLensPageKey: Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

struct ClawJSRuntimeLensPageSlice<Row> {
    let rows: [Row]
    let pageIndex: Int
    let pageCount: Int
    let totalCount: Int
    let pageSize: Int

    var hasPrevious: Bool { pageIndex > 0 }
    var hasNext: Bool { pageIndex + 1 < pageCount }
    var visibleStart: Int { totalCount == 0 ? 0 : pageIndex * pageSize + 1 }
    var visibleEnd: Int { min(totalCount, (pageIndex + 1) * pageSize) }
}

func clawJSRuntimeLensPage<C: Collection>(
    _ rows: C,
    pageIndex requestedPageIndex: Int,
    pageSize: Int
) -> ClawJSRuntimeLensPageSlice<C.Element> {
    let allRows = Array(rows)
    let safePageSize = max(1, pageSize)
    let pageCount = max(1, Int(ceil(Double(allRows.count) / Double(safePageSize))))
    let pageIndex = min(max(0, requestedPageIndex), pageCount - 1)
    let start = min(allRows.count, pageIndex * safePageSize)
    let end = min(allRows.count, start + safePageSize)
    return ClawJSRuntimeLensPageSlice(
        rows: Array(allRows[start..<end]),
        pageIndex: pageIndex,
        pageCount: pageCount,
        totalCount: allRows.count,
        pageSize: safePageSize
    )
}

struct ClawJSRuntimeLensPager<Row>: View {
    let slice: ClawJSRuntimeLensPageSlice<Row>
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        if slice.totalCount > slice.pageSize {
            HStack(spacing: 10) {
                Button("Previous", action: previous)
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(slice.hasPrevious ? Palette.textSecondary : Palette.textSecondary.opacity(0.45))
                    .disabled(!slice.hasPrevious)
                Text("\(slice.visibleStart)-\(slice.visibleEnd) of \(slice.totalCount)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.75))
                    .monospacedDigit()
                Button("Next", action: next)
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(slice.hasNext ? Palette.textSecondary : Palette.textSecondary.opacity(0.45))
                    .disabled(!slice.hasNext)
                Spacer()
            }
            .accessibilityLabel(Text("Runtime lens rows \(slice.visibleStart) through \(slice.visibleEnd) of \(slice.totalCount)"))
        }
    }
}

extension ClawJSRuntimeLensSection {
    func page<C: Collection>(_ rows: C, key: ClawJSRuntimeLensPageKey) -> ClawJSRuntimeLensPageSlice<C.Element> {
        clawJSRuntimeLensPage(rows, pageIndex: runtimeLensPages[key, default: 0], pageSize: Self.pageSize)
    }

    func setPage(_ key: ClawJSRuntimeLensPageKey, to pageIndex: Int) {
        runtimeLensPages[key] = max(0, pageIndex)
    }

    func pager<Row>(_ slice: ClawJSRuntimeLensPageSlice<Row>, key: ClawJSRuntimeLensPageKey) -> some View {
        ClawJSRuntimeLensPager(slice: slice) {
            setPage(key, to: slice.pageIndex - 1)
        } next: {
            setPage(key, to: slice.pageIndex + 1)
        }
    }

    func runtimeLensPresentationSection(_ section: ClawJSRuntimeLensSettingsPresentation.Section) -> some View {
        let pageKey = ClawJSRuntimeLensPageKey("settings-presentation-\(runtimeLensSelection.rawValue)-\(section.id)")
        let slice = page(section.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if section.id == "session-actions", runtimeLensSelection == .hermes {
                runtimeLensSessionActionControlHeader()
            }
            ForEach(slice.rows) { presentationRow in
                if section.id == "session-actions" {
                    runtimeLensPresentationRow(presentationRow, sectionId: section.id)
                } else {
                    runtimeLensPresentationRow(presentationRow)
                }
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-presentation-section-\(section.id)")
        .accessibilityLabel(Text(section.accessibilityLabel))
    }

    @ViewBuilder
    func runtimeLensDetailedInventory() -> some View {
        if let snapshot = runtimeLensSnapshots[runtimeLensSelection] {
            let inventory = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)
            if inventory.hasInventory {
                Divider().background(Color.overlay(0.07))
                runtimeLensInventory(snapshot, presentation: inventory)
            }
        }
    }

    func runtimeLensPresentationRow(
        _ presentationRow: ClawJSRuntimeLensSettingsPresentation.Row,
        sectionId: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            row(label: presentationRow.label) {
                HStack(spacing: 8) {
                    if let value = presentationRow.value {
                        Text(value)
                            .font(BodyFont.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ForEach(presentationRow.pills) { pill in
                        statusPill(text: pill.label, color: runtimeLensColor(pill.tone))
                    }
                    if sectionId == "session-actions" {
                        runtimeLensSessionActionButtons(action: presentationRow.id)
                    }
                    Spacer()
                }
            }
            ForEach(presentationRow.detailLines, id: \.self) { detailLine in
                Text(detailLine)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.74))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-presentation-row-\(presentationRow.id)")
        .accessibilityLabel(Text(presentationRow.accessibilityLabel))
    }

    func runtimeLensSessionActionControlHeader() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Session", text: $runtimeLensActionSessionId)
                    .textFieldStyle(.roundedBorder)
                    .font(BodyFont.system(size: 11.5))
                    .accessibilityIdentifier("runtime-lens-session-action-session-id")
                TextField("Message", text: $runtimeLensActionMessage)
                    .textFieldStyle(.roundedBorder)
                    .font(BodyFont.system(size: 11.5))
                    .accessibilityIdentifier("runtime-lens-session-action-message")
                TextField("Title", text: $runtimeLensActionTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(BodyFont.system(size: 11.5))
                    .accessibilityIdentifier("runtime-lens-session-action-title")
            }
            TextField("Loopback gateway URL", text: $runtimeLensActionGatewayURL)
                .textFieldStyle(.roundedBorder)
                .font(BodyFont.system(size: 11.5))
                .accessibilityIdentifier("runtime-lens-session-action-gateway-url")
            if let result = runtimeLensActionResult {
                Text(result)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("runtime-lens-session-action-result")
            }
        }
        .accessibilityIdentifier("runtime-lens-session-action-controls")
    }

    func runtimeLensSessionActionButtons(action: String) -> some View {
        let presentation = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: runtimeLensSelection,
            action: action,
            sessionId: runtimeLensActionSessionId,
            message: runtimeLensActionMessage,
            title: runtimeLensActionTitle,
            gatewayURL: runtimeLensActionGatewayURL,
            inFlightKeys: runtimeLensSessionActionsInFlight
        )

        return HStack(spacing: 6) {
            Button {
                Task { await runRuntimeLensSessionAction(action: action, confirmRuntimeWrite: false) }
            } label: {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(presentation.canCheckGate ? Palette.textPrimary : Palette.textSecondary.opacity(0.45))
            .help(presentation.disabledReason ?? "Check confirmation gate")
            .disabled(!presentation.canCheckGate)
            .accessibilityIdentifier("\(presentation.accessibilityIdentifier)-check")
            .accessibilityLabel(Text("\(presentation.accessibilityLabel), check confirmation gate"))

            Button {
                runtimeLensPendingConfirmedAction = action
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(presentation.canRunConfirmedFixture ? .orange : Palette.textSecondary.opacity(0.45))
            .help(presentation.disabledReason ?? "Run confirmed loopback fixture")
            .disabled(!presentation.canRunConfirmedFixture)
            .accessibilityIdentifier("\(presentation.accessibilityIdentifier)-run")
            .accessibilityLabel(Text("\(presentation.accessibilityLabel), run confirmed loopback fixture"))
        }
    }

    func row<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            trailing()
        }
    }

    func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
        }
    }

    func runtimeLensColor(_ tone: ClawJSRuntimeLensStatusTone) -> Color {
        switch tone {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        case .muted: return Color.overlay(0.35)
        }
    }
}
