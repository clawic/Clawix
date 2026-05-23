import Foundation

enum ClawixUserHomeRoutes {
    static let absoluteUsersPathRedactionPattern = #"/Users/[^\s"'`]+"#

    static func path() -> String {
        NSHomeDirectory()
    }

    static func directory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}
