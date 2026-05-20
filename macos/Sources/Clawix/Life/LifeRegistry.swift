import Foundation

/// Status of a vertical in the ClawJS Signals registry projection.
enum LifeVerticalStatus: String, Codable {
    case stable
    case devOnly = "dev_only"
    case removed

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "stable":
            self = .stable
        case "dev_only", "dev-only":
            self = .devOnly
        case "removed":
            self = .removed
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown life vertical status: \(rawValue)"
                )
            )
        }
    }
}

/// One of the ten top-level groupings that the Life sidebar uses to lay
/// out the 80 verticals. The raw value matches the ClawJS projection.
enum LifeCategory: String, Codable, CaseIterable {
    case bodyHealth = "body-health"
    case mindEmotions = "mind-emotions"
    case timeProductivity = "time-productivity"
    case creativeOutput = "creative-output"
    case consumptionLeisure = "consumption-leisure"
    case relationsSocial = "relations-social"
    case worldPlaces = "world-places"
    case possessionsIdentity = "possessions-identity"
    case careerMoney = "career-money"
    case metaReflection = "meta-reflection"

    var label: String {
        switch self {
        case .bodyHealth: return "Body & Health"
        case .mindEmotions: return "Mind & Emotions"
        case .timeProductivity: return "Time & Productivity"
        case .creativeOutput: return "Creative output"
        case .consumptionLeisure: return "Consumption & Leisure"
        case .relationsSocial: return "Relations & Social"
        case .worldPlaces: return "World & Places"
        case .possessionsIdentity: return "Possessions & Identity"
        case .careerMoney: return "Career & Money"
        case .metaReflection: return "Meta / Reflection"
        }
    }
}

/// One Clawix-renderable entry from the ClawJS Signals registry projection.
struct LifeRegistryEntry: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    let category: LifeCategory
    let description: String
    let catalogSize: Int
    let hasSessions: Bool
    let healthkitMapping: Bool
    let sensitive: Bool
    let status: LifeVerticalStatus
    let iconHint: String?

    var legalGuardLabel: String? {
        sensitive ? "SENSITIVE" : nil
    }

    var legalGuardDescription: String? {
        sensitive ? LegalSafetyPolicy.regulatedDecisionDisclaimer : nil
    }
}

private struct RegistryEnvelope: Decodable {
    let schemaVersion: Int
    let projectionVersion: String
    let source: RegistrySource
    let service: RegistryService
    let entries: [LifeRegistryEntry]
}

private struct RegistrySource: Decodable {
    let checksum: String
}

private struct RegistryService: Decodable {
    let port: Int
}

private struct LifeRegistrySnapshot {
    let entries: [LifeRegistryEntry]
    let projectionVersion: String
    let sourceChecksum: String
    let signalsServicePort: Int
}

private struct LifeFallbackEntry {
    let id: String
    let label: String
    let category: LifeCategory
    let iconHint: String?
    let sensitive: Bool
}

/// Caches the parsed generated projection per launch.
enum LifeRegistry {
    private static let snapshot: LifeRegistrySnapshot = loadSnapshot()

    static var entries: [LifeRegistryEntry] {
        entries(includeDevOnly: false)
    }

    static var projectionVersion: String {
        snapshot.projectionVersion
    }

    static var sourceChecksum: String {
        snapshot.sourceChecksum
    }

    static var signalsServicePort: Int {
        snapshot.signalsServicePort
    }

    static func entries(includeDevOnly: Bool) -> [LifeRegistryEntry] {
        snapshot.entries.filter { includeDevOnly || $0.status == .stable }
    }

    static func entry(byId id: String) -> LifeRegistryEntry? {
        snapshot.entries.first { $0.id == id && $0.status == .stable }
    }

    static func entry(byId id: String, includeDevOnly: Bool) -> LifeRegistryEntry? {
        snapshot.entries.first { entry in
            entry.id == id && (includeDevOnly || entry.status == .stable)
        }
    }

    static func entries(in category: LifeCategory, includeDevOnly: Bool = false) -> [LifeRegistryEntry] {
        snapshot.entries.filter { entry in
            entry.category == category && (includeDevOnly || entry.status == .stable)
        }
    }

    private static func loadSnapshot() -> LifeRegistrySnapshot {
        for bundle in [Bundle.module, Bundle.main] {
            if let url = bundle.url(forResource: "life-registry", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let envelope = try? JSONDecoder().decode(RegistryEnvelope.self, from: data) {
                return LifeRegistrySnapshot(
                    entries: envelope.entries,
                    projectionVersion: envelope.projectionVersion,
                    sourceChecksum: envelope.source.checksum,
                    signalsServicePort: envelope.service.port
                )
            }
        }
        return LifeRegistrySnapshot(
            entries: generatedFallbackEntries.map { entry in
                LifeRegistryEntry(
                    id: entry.id,
                    label: entry.label,
                    category: entry.category,
                    description: "",
                    catalogSize: 0,
                    hasSessions: false,
                    healthkitMapping: false,
                    sensitive: entry.sensitive,
                    status: .stable,
                    iconHint: entry.iconHint
                )
            },
            projectionVersion: "signals-registry.v1",
            sourceChecksum: generatedFallbackSourceChecksum,
            signalsServicePort: generatedFallbackSignalsServicePort
        )
    }

    private static let generatedFallbackSourceChecksum = "sha256:baL7wluzu61bF2XNMAblb-kW9tpE1drqELnc6LW_I2M"
    private static let generatedFallbackSignalsServicePort = 24110
    private static let generatedFallbackEntries: [LifeFallbackEntry] = [
        // BEGIN GENERATED LIFE FALLBACK
        LifeFallbackEntry(id: "health", label: "Health", category: .bodyHealth, iconHint: "heart", sensitive: true),
        LifeFallbackEntry(id: "sleep", label: "Sleep", category: .bodyHealth, iconHint: "moon", sensitive: false),
        LifeFallbackEntry(id: "nutrition", label: "Nutrition", category: .bodyHealth, iconHint: "apple", sensitive: false),
        LifeFallbackEntry(id: "workouts", label: "Workouts", category: .bodyHealth, iconHint: "dumbbell", sensitive: false),
        LifeFallbackEntry(id: "emotions", label: "Emotions", category: .mindEmotions, iconHint: "smile", sensitive: false),
        LifeFallbackEntry(id: "journal", label: "Journal", category: .mindEmotions, iconHint: "book", sensitive: false),
        LifeFallbackEntry(id: "habits", label: "Habits", category: .timeProductivity, iconHint: "check", sensitive: false),
        LifeFallbackEntry(id: "time-tracking", label: "Time tracking", category: .timeProductivity, iconHint: "timer", sensitive: false),
        LifeFallbackEntry(id: "finance", label: "Finance", category: .careerMoney, iconHint: "wallet", sensitive: true),
        LifeFallbackEntry(id: "goals", label: "Goals", category: .metaReflection, iconHint: "flag", sensitive: false)
        // END GENERATED LIFE FALLBACK
    ]
}
