import SwiftUI

/// Custom URL scheme used by project rows in the sidebar's "Custom" sort
/// mode to encode the dragged project's id as `clawix-project:<UUID>`.
/// NSURL drags conform to `public.url` (a sibling of
/// `public.utf8-plain-text` under `public.data`), so the project reorder
/// drag does NOT match `ChatDropTarget`'s `.onDrop(of: [.text])` and
/// can't be misrouted into `moveChatToProject`. Going through a system
/// UTI also sidesteps having to declare a custom UTI in `Info.plist`,
/// which `UTType(importedAs:)` without an `Info.plist` declaration
/// requires for SwiftUI's `.onDrop(of:)` filter to recognise it.
let clawixProjectURLScheme = "clawix-project"

/// Custom URL scheme used by tool rows in the sidebar's "Tools" section
/// when reordering. Same rationale as `clawixProjectURLScheme`: registering
/// the drag as `public.url` keeps it invisible to chat / project drop
/// targets, which match different schemes.
let clawixToolURLScheme = "clawix-tool"

/// Catalog of every entry rendered in the sidebar's `Tools` section.
/// The IDs are stable strings (NOT route descriptions) so the user's
/// custom order persists even if a route's path changes; new tools added
/// in future releases simply append at the bottom of the saved order on
/// first launch.
enum SidebarToolIcon: Equatable {
    case system(String)
    case secrets
    case clawixLogo
}

struct SidebarToolEntry: Identifiable, Equatable {
    let id: String
    let title: LocalizedStringKey
    let titleString: String
    let icon: SidebarToolIcon
    let route: SidebarRoute

    static func == (lhs: SidebarToolEntry, rhs: SidebarToolEntry) -> Bool {
        lhs.id == rhs.id
            && lhs.titleString == rhs.titleString
            && lhs.icon == rhs.icon
            && lhs.route == rhs.route
    }
}

enum SidebarToolsCatalog {
    static let entries: [SidebarToolEntry] = [
        SidebarToolEntry(id: "home",      title: "Home",      titleString: "Home",
                         icon: .system("house"),                     route: .iotHome),
        SidebarToolEntry(id: "tasks",     title: "Tasks",     titleString: "Tasks",
                         icon: .system("checkmark.circle"),          route: .databaseCollection("tasks")),
        SidebarToolEntry(id: "goals",     title: "Goals",     titleString: "Goals",
                         icon: .system("flag"),                      route: .databaseCollection("goals")),
        SidebarToolEntry(id: "notes",     title: "Notes",     titleString: "Notes",
                         icon: .system("note.text"),                 route: .databaseCollection("notes")),
        SidebarToolEntry(id: "calendar",  title: "Calendar",  titleString: "Calendar",
                         icon: .system("calendar"),                  route: .calendarHome),
        SidebarToolEntry(id: "contacts",  title: "Contacts",  titleString: "Contacts",
                         icon: .system("person.crop.circle"),        route: .contactsHome),
        SidebarToolEntry(id: "projects",  title: "Projects",  titleString: "Projects",
                         icon: .system("square.stack.3d.up"),        route: .databaseCollection("projects")),
        SidebarToolEntry(id: "secrets",   title: "Secrets",   titleString: "Secrets",
                         icon: .secrets,                             route: .secretsHome),
        SidebarToolEntry(id: "memory",    title: "Memory",    titleString: "Memory",
                         icon: .system("brain"),                     route: .memoryHome),
        SidebarToolEntry(id: "database",  title: "Database",  titleString: "Database",
                         icon: .system("cylinder.split.1x2"),        route: .databaseHome),
        SidebarToolEntry(id: "index",     title: "Index",     titleString: "Index",
                         icon: .system("books.vertical"),            route: .indexHome),
        SidebarToolEntry(id: "macCare",   title: "Mac Care",  titleString: "Mac Care",
                         icon: .system("wrench.and.screwdriver"),    route: .macCare),
        SidebarToolEntry(id: "marketplace", title: "Marketplace", titleString: "Marketplace",
                         icon: .system("handshake"),                 route: .marketplaceHome),
        SidebarToolEntry(id: "photos",    title: "Photos",    titleString: "Photos",
                         icon: .system("photo.on.rectangle.angled"), route: .drivePhotos),
        SidebarToolEntry(id: "documents", title: "Documents", titleString: "Documents",
                         icon: .system("doc.text"),                  route: .driveDocuments),
        SidebarToolEntry(id: "recent",    title: "Recent",    titleString: "Recent",
                         icon: .system("clock.arrow.circlepath"),    route: .driveRecent),
        SidebarToolEntry(id: "drive",     title: "Drive",     titleString: "Drive",
                         icon: .system("internaldrive"),             route: .driveAdmin),
        SidebarToolEntry(id: "personalities", title: "Personalities", titleString: "Personalities",
                         icon: .system("theatermasks"),              route: .personalitiesHome),
        SidebarToolEntry(id: "skillCollections", title: "Skill Collections", titleString: "Skill Collections",
                         icon: .system("square.stack"),              route: .skillCollectionsHome),
        SidebarToolEntry(id: "connections", title: "Connections", titleString: "Connections",
                         icon: .system("link.circle"),               route: .connectionsHome),
        SidebarToolEntry(id: "network", title: "Network", titleString: "Network",
                         icon: .system("network"),                   route: .networkControl),
        SidebarToolEntry(id: "publishing",    title: "Publishing",    titleString: "Publishing",
                         icon: .system("megaphone"),                 route: .publishingHome),
    ]

    static func entry(byId id: String) -> SidebarToolEntry? {
        entries.first { $0.id == id }
    }

    static func gatedFeature(for id: String) -> AppFeature? {
        switch id {
        case "network":          return .networkControl
        case "home":             return .iotHome
        case "calendar":         return .calendar
        case "contacts":         return .contacts
        case "secrets":          return .secrets
        case "database":         return .database
        case "index":            return .index
        case "macCare":          return nil
        case "marketplace":      return .marketplace
        case "personalities":    return .agents
        case "skillCollections": return .skillCollections
        case "connections":      return .agents
        case "publishing":           return .publishing
        default:                 return nil
        }
    }
}

/// Top-level layout of the chat list. Either group chats under their
/// project (with a "Chats" bucket for the projectless ones) or render a
/// single flat chronological list.
enum SidebarViewMode: String { case grouped, chronological }

/// How projects are ordered when `viewMode == .grouped`. `.custom` lets
/// the user drag-reorder the list; the order is persisted via
/// `ProjectOrdersRepository`.
enum ProjectSortMode: String { case recent, creation, name, custom }

/// UserDefaults suite used to persist sidebar preferences across launches.
/// Same suite already used for the main window frame and browser state.
enum SidebarPrefs {
    static let store: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard

    /// Read a Bool with a fallback for keys that have never been written.
    /// `UserDefaults.bool(forKey:)` returns `false` for missing keys, which
    /// would silently flip our "expanded by default" sections on first run.
    static func bool(forKey key: String, default fallback: Bool) -> Bool {
        if store.object(forKey: key) == nil { return fallback }
        return store.bool(forKey: key)
    }
}
