import Foundation
import GRDB

// @persistent-surface-wrapper
enum ClawixRegisteredDatabaseQueue {
    static func open(path: String, configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try DatabaseQueue(path: path, configuration: configuration)
    }

    static func open(url: URL, configuration: Configuration = Configuration()) throws -> DatabaseQueue {
        try open(path: url.path, configuration: configuration)
    }
}
