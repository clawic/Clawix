import Foundation

struct ClawJSRuntimeLensSupportOverviewPresentation: Equatable {
    let adapterSupportLevel: String?
    let adapterStability: String?
    let adapterRecommended: Bool?
    let ecosystemSupportStage: String?
    let ecosystemRecommended: Bool?
    let ecosystemProduction: Bool?
    let uiParityClaim: String?
    let summary: String?
    let claimSource: String?
    let provenanceSource: String?
    let provenanceRuntimeId: String?
    let sourceLabel: String?
    let officialSnapshotCapturedAt: String?
    let officialSnapshotSourceSnapshotDate: String?
    let officialSnapshotSourceCount: Int
    let officialSnapshotLabel: String?
    let officialSnapshotDriftPolicy: String?
    let blockingReasonCount: Int
    let blockingReasonsLabel: String?
    let evidenceRequirementCount: Int
    let notPromoted: Bool
    let hasSummary: Bool

    var accessibilityLabel: String {
        [
            "Runtime support overview",
            "adapter \(adapterSupportLevel ?? "unknown")",
            "ecosystem \(ecosystemSupportStage ?? "unknown")",
            "recommended \(ecosystemRecommended == true)",
            "production \(ecosystemProduction == true)",
            "not promoted \(notPromoted)",
            claimSource.map { "claim source \($0)" },
            provenanceSource.map { "provenance source \($0)" },
            provenanceRuntimeId.map { "provenance runtime \($0)" },
            officialSnapshotCapturedAt.map { "official snapshot \($0)" },
            officialSnapshotSourceSnapshotDate.map { "source snapshot \($0)" },
            "official sources \(officialSnapshotSourceCount)",
            "blockers \(blockingReasonCount)",
            "evidence \(evidenceRequirementCount)",
            "summary \(hasSummary)"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        support: ClawJSRuntimeLensSnapshot.Support
    ) -> ClawJSRuntimeLensSupportOverviewPresentation {
        let adapterSupportLevel = normalized(support.adapter?.supportLevel) ?? normalized(support.supportLevel)
        let adapterStability = normalized(support.adapter?.stability) ?? normalized(support.stability)
        let adapterRecommended = support.adapter?.recommended ?? support.recommended
        let ecosystem = support.ecosystem
        let summary = normalized(ecosystem?.summary)
        let blockingReasons = (ecosystem?.blockingReasons ?? []).compactMap(normalized)
        let evidenceRequirementCount = ecosystem?.evidenceRequirements?.count ?? 0
        let ecosystemRecommended = ecosystem?.recommended
        let ecosystemProduction = ecosystem?.production
        let notPromoted = ecosystemRecommended == false || ecosystemProduction == false
        let claimSource = normalized(ecosystem?.claimSource)
        let provenanceSource = normalized(ecosystem?.provenance?.source)
        let provenanceRuntimeId = normalized(ecosystem?.provenance?.runtimeId)
        let officialSnapshot = ecosystem?.officialSnapshot
        let officialSnapshotCapturedAt = normalized(officialSnapshot?.capturedAt)
        let officialSnapshotSourceSnapshotDate = normalized(officialSnapshot?.sourceSnapshotDate)
        let officialSnapshotSources = officialSnapshot?.sources ?? []
        let officialSnapshotDriftPolicy = normalized(officialSnapshot?.driftPolicy)

        return ClawJSRuntimeLensSupportOverviewPresentation(
            adapterSupportLevel: adapterSupportLevel,
            adapterStability: adapterStability,
            adapterRecommended: adapterRecommended,
            ecosystemSupportStage: normalized(ecosystem?.supportStage),
            ecosystemRecommended: ecosystemRecommended,
            ecosystemProduction: ecosystemProduction,
            uiParityClaim: normalized(ecosystem?.uiParityClaim),
            summary: summary,
            claimSource: claimSource,
            provenanceSource: provenanceSource,
            provenanceRuntimeId: provenanceRuntimeId,
            sourceLabel: sourceLabel(
                claimSource: claimSource,
                provenanceSource: provenanceSource,
                provenanceRuntimeId: provenanceRuntimeId
            ),
            officialSnapshotCapturedAt: officialSnapshotCapturedAt,
            officialSnapshotSourceSnapshotDate: officialSnapshotSourceSnapshotDate,
            officialSnapshotSourceCount: officialSnapshotSources.count,
            officialSnapshotLabel: officialSnapshotLabel(
                capturedAt: officialSnapshotCapturedAt,
                sourceSnapshotDate: officialSnapshotSourceSnapshotDate,
                sourceCount: officialSnapshotSources.count
            ),
            officialSnapshotDriftPolicy: officialSnapshotDriftPolicy,
            blockingReasonCount: blockingReasons.count,
            blockingReasonsLabel: blockingReasons.isEmpty
                ? nil
                : blockingReasons.joined(separator: ", "),
            evidenceRequirementCount: evidenceRequirementCount,
            notPromoted: notPromoted,
            hasSummary: summary != nil
        )
    }

    private static func sourceLabel(
        claimSource: String?,
        provenanceSource: String?,
        provenanceRuntimeId: String?
    ) -> String? {
        let source = provenanceSource ?? claimSource
        let parts = [
            source,
            provenanceRuntimeId.map { "runtime \($0)" },
            claimSource.flatMap { claimSource in
                claimSource == source ? nil : "claim \(claimSource)"
            }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func officialSnapshotLabel(
        capturedAt: String?,
        sourceSnapshotDate: String?,
        sourceCount: Int
    ) -> String? {
        let parts = [
            capturedAt.map { "captured \($0)" },
            sourceSnapshotDate.map { "source snapshot \($0)" },
            sourceCount > 0 ? "sources \(sourceCount)" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
