import Foundation

struct AppBridgeDBQuery: Equatable {
    var collection: String
    var filterChips: [DBFilterState.Chip]
    var search: String
    var sort: DBFilterState.Sort?
    var limit: Int
    var offset: Int

    var hasClientSideFilters: Bool {
        !search.isEmpty || filterChips.contains { $0.op != .eq }
    }

    var backendFilterJSON: [String: Any]? {
        var filter: [String: Any] = [:]
        for chip in filterChips where chip.op == .eq {
            filter[chip.field] = chip.value.foundationValue
        }
        return filter.isEmpty ? nil : filter
    }

    var sortString: String? {
        guard let sort else { return nil }
        return sort.descending ? "-\(sort.field)" : sort.field
    }

    func postFilter(_ records: [DBRecord]) -> [DBRecord] {
        DBFilterState(chips: filterChips, sort: sort, search: search)
            .clientSidePostFilter(records: records)
    }
}

struct AppBridgeSearchQuery: Equatable {
    var query: String
    var collections: [String]
    var limit: Int
}

enum AppBridgeQueryDSL {
    enum QueryError: LocalizedError, Equatable {
        case missingCollection
        case missingQuery
        case unsupportedFilter(String)

        var errorDescription: String? {
            switch self {
            case .missingCollection:
                return "db.query requires a collection."
            case .missingQuery:
                return "search.query requires a query."
            case .unsupportedFilter(let field):
                return "Unsupported filter for field: \(field)"
            }
        }
    }

    static func dbQuery(from payload: [String: Any]) throws -> AppBridgeDBQuery {
        let collection = string(payload["collection"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collection.isEmpty else { throw QueryError.missingCollection }

        let filter = try filterChips(from: payload["filter"])
        let search = string(payload["search"] ?? payload["query"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sort = sort(from: payload["sort"])

        return AppBridgeDBQuery(
            collection: collection,
            filterChips: filter,
            search: search,
            sort: sort,
            limit: clampedInt(payload["limit"], defaultValue: 50, min: 1, max: 100),
            offset: clampedInt(payload["offset"], defaultValue: 0, min: 0, max: 10_000)
        )
    }

    static func searchQuery(from payload: [String: Any]) throws -> AppBridgeSearchQuery {
        let query = string(payload["query"] ?? payload["text"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw QueryError.missingQuery }

        return AppBridgeSearchQuery(
            query: query,
            collections: stringArray(payload["collections"]),
            limit: clampedInt(payload["limit"], defaultValue: 25, min: 1, max: 100)
        )
    }

    static func bridgeValue(collection: String, record: DBRecord) -> [String: Any] {
        var data: [String: Any] = [:]
        for (key, value) in record.data {
            data[key] = value.foundationValue
        }
        return [
            "id": record.id,
            "collection": collection,
            "title": record.titleString,
            "createdAt": record.createdAt,
            "updatedAt": record.updatedAt,
            "data": data
        ]
    }

    private static func filterChips(from value: Any?) throws -> [DBFilterState.Chip] {
        guard let dict = value as? [String: Any] else { return [] }
        var chips: [DBFilterState.Chip] = []
        for (field, rawValue) in dict {
            let trimmedField = field.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedField.isEmpty else { continue }
            if let opDict = rawValue as? [String: Any] {
                if let value = opDict["eq"] {
                    chips.append(.init(field: trimmedField, op: .eq, value: json(value)))
                } else if let value = opDict["neq"] {
                    chips.append(.init(field: trimmedField, op: .neq, value: json(value)))
                } else if bool(opDict["isNull"]) == true {
                    chips.append(.init(field: trimmedField, op: .isNull, value: .null))
                } else if bool(opDict["notNull"]) == true {
                    chips.append(.init(field: trimmedField, op: .notNull, value: .null))
                } else {
                    throw QueryError.unsupportedFilter(trimmedField)
                }
            } else {
                chips.append(.init(field: trimmedField, op: .eq, value: json(rawValue)))
            }
        }
        return chips
    }

    private static func sort(from value: Any?) -> DBFilterState.Sort? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.hasPrefix("-") {
                return .init(field: String(trimmed.dropFirst()), descending: true)
            }
            return .init(field: trimmed, descending: false)
        }
        guard let dict = value as? [String: Any] else { return nil }
        let field = string(dict["field"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !field.isEmpty else { return nil }
        let descending = bool(dict["descending"]) ?? (string(dict["direction"]).lowercased() == "desc")
        return .init(field: field, descending: descending)
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array
            .map { string($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func clampedInt(_ value: Any?, defaultValue: Int, min: Int, max: Int) -> Int {
        let raw: Int
        if let int = value as? Int {
            raw = int
        } else if let number = value as? NSNumber {
            raw = number.intValue
        } else if let string = value as? String, let int = Int(string) {
            raw = int
        } else {
            raw = defaultValue
        }
        return Swift.max(min, Swift.min(max, raw))
    }

    private static func string(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func json(_ value: Any?) -> DBJSON {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            if double.rounded() == double {
                return .integer(number.int64Value)
            }
            return .number(double)
        }
        if let dict = value as? [String: Any] {
            return .object(dict.mapValues(json))
        }
        if let array = value as? [Any] {
            return .array(array.map(json))
        }
        return DBJSON.wrap(value)
    }
}
