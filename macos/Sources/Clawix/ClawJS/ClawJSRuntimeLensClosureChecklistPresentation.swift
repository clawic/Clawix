import Foundation

struct ClawJSRuntimeLensClosureChecklistPresentation: Equatable {
    struct StatusPill: Equatable, Identifiable {
        var id: String { status }
        let status: String
        let count: Int

        var label: String {
            "\(status) \(count)"
        }
    }

    struct Row: Equatable, Identifiable {
        var id: String { domain }
        let domain: String
        let closureStatus: String
        let claim: String?
        let runtimeStatus: String?
        let safeDefault: String?
        let nextAction: String?
        let evidenceCount: Int
        let evidenceRequirementIdsLabel: String?
        let readProjectionStatus: String?
        let implementedFacetCount: Int
        let blockingFacetCount: Int
        let projectionDisposition: String?
        let writeBackPolicy: String?
        let validation: String?
        let blockerClassesLabel: String?
        let supportResolutionsLabel: String?

        var accessibilityLabel: String {
            [
                domain,
                closureStatus,
                claim.map { "claim \($0)" },
                runtimeStatus.map { "runtime status \($0)" },
                readProjectionStatus.map { "read projection \($0)" },
                projectionDisposition.map { "projection disposition \($0)" },
                writeBackPolicy.map { "write back \($0)" },
                validation.map { "validation \($0)" },
                blockerClassesLabel.map { "blocker classes \($0)" },
                evidenceRequirementIdsLabel.map { "evidence ids \($0)" },
                supportResolutionsLabel.map { "support resolutions \($0)" },
                "implemented facets \(implementedFacetCount)",
                "blocking facets \(blockingFacetCount)",
                safeDefault.map { "safe default \($0)" },
                nextAction.map { "next action \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let totalLabel: String
    let statusPills: [StatusPill]
    let rows: [Row]

    var accessibilityLabel: String {
        let statuses = statusPills.map(\.label).joined(separator: ", ")
        let domains = rows.map { "\($0.domain) \($0.closureStatus)" }.joined(separator: ", ")
        return ["Runtime closure checklist", totalLabel, statuses, domains]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func make(
        checklist: [ClawJSRuntimeLensSnapshot.SupportAudit.ClosureChecklistItem],
        summary: [String: Int]?
    ) -> ClawJSRuntimeLensClosureChecklistPresentation {
        let statusPills = (summary ?? [:])
            .keys
            .sorted()
            .prefix(3)
            .map { StatusPill(status: $0, count: summary?[$0] ?? 0) }
        let blockedRows = checklist.filter { $0.closureStatus != "implemented_or_projected" }
        let visibleRows = (blockedRows.isEmpty ? checklist : blockedRows)
            .prefix(2)
            .map {
                Row(
                    domain: $0.domain,
                    closureStatus: $0.closureStatus ?? "unknown",
                    claim: $0.claim,
                    runtimeStatus: $0.status,
                    safeDefault: $0.safeDefault,
                    nextAction: $0.nextAction,
                    evidenceCount: $0.evidenceRequirementIds?.count ?? 0,
                    evidenceRequirementIdsLabel: listLabel($0.evidenceRequirementIds, limit: 3),
                    readProjectionStatus: $0.readProjectionStatus,
                    implementedFacetCount: $0.implementedFacets?.count ?? 0,
                    blockingFacetCount: $0.blockingFacets?.count ?? 0,
                    projectionDisposition: $0.projectionDisposition,
                    writeBackPolicy: $0.writeBackPolicy,
                    validation: $0.validation,
                    blockerClassesLabel: listLabel($0.blockerClasses, limit: 3),
                    supportResolutionsLabel: listLabel($0.supportResolutions, limit: 3)
                )
            }

        return ClawJSRuntimeLensClosureChecklistPresentation(
            totalLabel: "closure \(checklist.count)",
            statusPills: Array(statusPills),
            rows: Array(visibleRows)
        )
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
