import Foundation

struct ClawJSRuntimeLensInventoryPresentation: Equatable {
    struct Section: Equatable, Identifiable {
        let id: String
        let domain: String
        let displayLabel: String
        let totalResourceCount: Int
        let visibleResourceCount: Int
        let statusLabel: String?
        let pinnedCount: Int
        let pathCount: Int
        let updatedCount: Int
        let kindCount: Int
        let summaryCount: Int
        let enabledCount: Int
        let sizeCount: Int
        let rows: [Row]

        var accessibilityLabel: String {
            [
                "runtime inventory domain \(domain)",
                "label \(displayLabel)",
                "resources \(totalResourceCount)",
                "visible \(visibleResourceCount)",
                statusLabel.map { "statuses \($0)" },
                "pinned \(pinnedCount)",
                "paths \(pathCount)",
                "updated \(updatedCount)",
                "kinds \(kindCount)",
                "summaries \(summaryCount)",
                "enabled states \(enabledCount)",
                "sizes \(sizeCount)"
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let resource: ClawJSRuntimeLensSnapshot.RuntimeResource
        let displayLabel: String
        let statusLabel: String?
        let kind: String?
        let path: String?
        let summary: String?
        let updatedAt: String?
        let enabled: Bool?
        let sizeBytes: Int?
        let pinned: Bool
        let nativeIdentifierName: String?
        let provenanceSource: String?
        let provenanceRuntimeId: String?
        let provenancePath: String?
        let limitations: [String]
        let attributes: [String]

        var kindLabel: String? {
            guard let kind else { return nil }
            return "kind: \(kind)"
        }

        var summaryLabel: String? {
            guard let summary else { return nil }
            return summary
        }

        var enabledLabel: String? {
            guard let enabled else { return nil }
            return enabled ? "enabled: true" : "enabled: false"
        }

        var sizeLabel: String? {
            guard let sizeBytes else { return nil }
            return "\(sizeBytes) B"
        }

        var nativeIdentifierLabel: String? {
            guard let nativeIdentifierName else { return nil }
            return "native id: \(nativeIdentifierName)"
        }

        var provenanceLabel: String? {
            let values = [
                provenanceSource,
                provenanceRuntimeId.map { "runtime \($0)" },
                provenancePath
            ]
            .compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var limitationCount: Int {
            limitations.count
        }

        var limitationsLabel: String? {
            ClawJSRuntimeLensInventoryPresentation.listLabel(limitations, limit: 3)
        }

        var attributeCount: Int {
            attributes.count
        }

        var attributesLabel: String? {
            ClawJSRuntimeLensInventoryPresentation.listLabel(attributes, limit: 4)
        }

        var accessibilityLabel: String {
            [
                "runtime inventory resource \(id)",
                "label \(displayLabel)",
                statusLabel.map { "status \($0)" },
                kind.map { "kind \($0)" },
                path.map { "path \($0)" },
                summary.map { "summary \($0)" },
                updatedAt.map { "updated \($0)" },
                enabled.map { "enabled \($0)" },
                sizeBytes.map { "size bytes \($0)" },
                "pinned \(pinned)",
                nativeIdentifierName.map { "native identifier \($0)" },
                provenanceSource.map { "provenance source \($0)" },
                provenanceRuntimeId.map { "provenance runtime \($0)" },
                provenancePath.map { "provenance path \($0)" },
                "limitations \(limitationCount)",
                limitationsLabel.map { "limitations \($0)" },
                "attributes \(attributeCount)",
                attributesLabel.map { "attributes \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let sectionCount: Int
    let totalResourceCount: Int
    let visibleResourceCount: Int
    let pinnedResourceCount: Int
    let pathResourceCount: Int
    let updatedResourceCount: Int
    let kindResourceCount: Int
    let summaryResourceCount: Int
    let enabledResourceCount: Int
    let sizedResourceCount: Int
    let nativeIdentifierResourceCount: Int
    let provenanceResourceCount: Int
    let limitationResourceCount: Int
    let limitationCount: Int
    let attributeResourceCount: Int
    let attributeCount: Int
    let domainLabel: String?
    let sections: [Section]

    var hasInventory: Bool {
        !sections.isEmpty
    }

    var accessibilityLabel: String {
        [
            "Runtime inventory",
            "domains \(sectionCount)",
            "resources \(totalResourceCount)",
            "visible \(visibleResourceCount)",
            "pinned \(pinnedResourceCount)",
            "paths \(pathResourceCount)",
            "updated \(updatedResourceCount)",
            "kinds \(kindResourceCount)",
            "summaries \(summaryResourceCount)",
            "enabled states \(enabledResourceCount)",
            "sizes \(sizedResourceCount)",
            "native identifiers \(nativeIdentifierResourceCount)",
            "provenance \(provenanceResourceCount)",
            "limitation resources \(limitationResourceCount)",
            "limitations \(limitationCount)",
            "attribute resources \(attributeResourceCount)",
            "attributes \(attributeCount)",
            domainLabel.map { "inventory domains \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        snapshot: ClawJSRuntimeLensSnapshot,
        rowLimit: Int = 5
    ) -> ClawJSRuntimeLensInventoryPresentation {
        let sections = ClawJSRuntimeLensSnapshot.canonicalDomains.compactMap { domain -> Section? in
            let resources = snapshot.resources(for: domain)
            guard !resources.isEmpty else { return nil }
            let rows = resources.prefix(rowLimit).map { resource in
                Row(
                    id: resource.id,
                    resource: resource,
                    displayLabel: resource.displayLabel,
                    statusLabel: statusLabel(for: resource),
                    kind: resource.kind,
                    path: resource.path,
                    summary: resource.summary,
                    updatedAt: resource.updatedAt,
                    enabled: resource.enabled,
                    sizeBytes: resource.sizeBytes,
                    pinned: resource.pinned == true,
                    nativeIdentifierName: resource.nativeIdentifier?.name,
                    provenanceSource: resource.provenance?.source,
                    provenanceRuntimeId: resource.provenance?.runtimeId,
                    provenancePath: resource.provenance?.path,
                    limitations: resource.limitations ?? [],
                    attributes: resource.attributes ?? []
                )
            }

            return Section(
                id: domain,
                domain: domain,
                displayLabel: ClawJSRuntimeLensSnapshot.displayLabel(for: domain),
                totalResourceCount: resources.count,
                visibleResourceCount: rows.count,
                statusLabel: countLabel(resources.compactMap { statusLabel(for: $0) }),
                pinnedCount: resources.filter { $0.pinned == true }.count,
                pathCount: resources.filter { $0.path != nil }.count,
                updatedCount: resources.filter { $0.updatedAt != nil }.count,
                kindCount: resources.filter { $0.kind != nil }.count,
                summaryCount: resources.filter { $0.summary != nil }.count,
                enabledCount: resources.filter { $0.enabled != nil }.count,
                sizeCount: resources.filter { $0.sizeBytes != nil }.count,
                rows: rows
            )
        }

        return ClawJSRuntimeLensInventoryPresentation(
            sectionCount: sections.count,
            totalResourceCount: sections.reduce(0) { $0 + $1.totalResourceCount },
            visibleResourceCount: sections.reduce(0) { $0 + $1.visibleResourceCount },
            pinnedResourceCount: sections.reduce(0) { $0 + $1.pinnedCount },
            pathResourceCount: sections.reduce(0) { $0 + $1.pathCount },
            updatedResourceCount: sections.reduce(0) { $0 + $1.updatedCount },
            kindResourceCount: sections.reduce(0) { $0 + $1.kindCount },
            summaryResourceCount: sections.reduce(0) { $0 + $1.summaryCount },
            enabledResourceCount: sections.reduce(0) { $0 + $1.enabledCount },
            sizedResourceCount: sections.reduce(0) { $0 + $1.sizeCount },
            nativeIdentifierResourceCount: sections.reduce(0) { total, section in
                total + section.rows.filter { $0.nativeIdentifierName != nil }.count
            },
            provenanceResourceCount: sections.reduce(0) { total, section in
                total + section.rows.filter { $0.provenanceLabel != nil }.count
            },
            limitationResourceCount: sections.reduce(0) { total, section in
                total + section.rows.filter { !$0.limitations.isEmpty }.count
            },
            limitationCount: sections.reduce(0) { total, section in
                total + section.rows.reduce(0) { $0 + $1.limitationCount }
            },
            attributeResourceCount: sections.reduce(0) { total, section in
                total + section.rows.filter { !$0.attributes.isEmpty }.count
            },
            attributeCount: sections.reduce(0) { total, section in
                total + section.rows.reduce(0) { $0 + $1.attributeCount }
            },
            domainLabel: listLabel(sections.map(\.domain), limit: 6),
            sections: sections
        )
    }

    private static func statusLabel(for resource: ClawJSRuntimeLensSnapshot.RuntimeResource) -> String? {
        if let status = resource.status { return status }
        if resource.enabled == false { return "disabled" }
        return nil
    }

    private static func countLabel(_ values: [String]) -> String? {
        let counts = values.reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        let pairs = counts.sorted { $0.key < $1.key }
        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    private static func listLabel(_ values: [String], limit: Int) -> String? {
        guard !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
