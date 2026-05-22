import Foundation

struct ClawJSRuntimeLensMissingDomainPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let domain: String
        let displayLabel: String

        var accessibilityLabel: String {
            "runtime missing domain \(domain), label \(displayLabel)"
        }
    }

    let totalCanonicalDomainCount: Int
    let presentDomainCount: Int
    let missingDomainCount: Int
    let coverageStatus: String
    let missingDomainsLabel: String?
    let rows: [Row]

    var hasMissingDomains: Bool {
        !rows.isEmpty
    }

    var accessibilityLabel: String {
        [
            "Runtime missing domains",
            coverageStatus,
            "canonical domains \(totalCanonicalDomainCount)",
            "present \(presentDomainCount)",
            "missing \(missingDomainCount)",
            missingDomainsLabel.map { "missing domains \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        domains: [ClawJSRuntimeLensSnapshot.Domain],
        canonicalDomains: [String] = ClawJSRuntimeLensSnapshot.canonicalDomains
    ) -> ClawJSRuntimeLensMissingDomainPresentation {
        let present = Set(domains.map(\.domain))
        let missing = canonicalDomains.filter { !present.contains($0) }
        let rows = missing.map { domain in
            Row(
                id: domain,
                domain: domain,
                displayLabel: ClawJSRuntimeLensSnapshot.displayLabel(for: domain)
            )
        }

        return ClawJSRuntimeLensMissingDomainPresentation(
            totalCanonicalDomainCount: canonicalDomains.count,
            presentDomainCount: canonicalDomains.count - missing.count,
            missingDomainCount: missing.count,
            coverageStatus: missing.isEmpty ? "all_domains_accounted" : "semantic_lens_incomplete",
            missingDomainsLabel: listLabel(missing, limit: 8),
            rows: rows
        )
    }

    private static func listLabel(_ values: [String], limit: Int) -> String? {
        guard !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
