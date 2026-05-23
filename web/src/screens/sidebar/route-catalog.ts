export type AppRoute =
  | "chat"
  | "search"
  | "skills"
  | "network"
  | "plugins"
  | "automations"
  | "home"
  | "tasks"
  | "goals"
  | "notes"
  | "calendar"
  | "contacts"
  | "projects"
  | "secrets"
  | "memory"
  | "database"
  | "index"
  | "mac-care"
  | "marketplace"
  | "photos"
  | "documents"
  | "recent"
  | "drive"
  | "agents"
  | "personalities"
  | "skill-collections"
  | "connections"
  | "publishing"
  | "pomodoro"
  | "mcp"
  | "local-models"
  | "settings";

export type RouteSectionId = "primary" | "tools" | "runtime" | "settings";

export interface RouteCatalogEntry {
  route: AppRoute;
  label: string;
  section: RouteSectionId;
  macToolId?: string;
  macRoute: string;
  webSurface: "implemented" | "companion" | "placeholder";
}

export const PRIMARY_ROUTE_ENTRIES: RouteCatalogEntry[] = [
  { route: "chat", label: "Chats", section: "primary", macRoute: "home/chat", webSurface: "implemented" },
  { route: "search", label: "Search", section: "primary", macRoute: "search", webSurface: "implemented" },
  { route: "skills", label: "Skills", section: "primary", macRoute: "skills", webSurface: "implemented" },
  { route: "network", label: "Network", section: "primary", macToolId: "network", macRoute: "networkControl", webSurface: "implemented" },
  { route: "plugins", label: "Plugins", section: "primary", macRoute: "plugins", webSurface: "implemented" },
  { route: "automations", label: "Automations", section: "primary", macRoute: "automations", webSurface: "implemented" },
];

export const MAC_SIDEBAR_TOOL_ENTRIES: RouteCatalogEntry[] = [
  { route: "home", label: "Home", section: "tools", macToolId: "home", macRoute: "iotHome", webSurface: "companion" },
  { route: "tasks", label: "Tasks", section: "tools", macToolId: "tasks", macRoute: "databaseCollection(tasks)", webSurface: "implemented" },
  { route: "goals", label: "Goals", section: "tools", macToolId: "goals", macRoute: "databaseCollection(goals)", webSurface: "implemented" },
  { route: "notes", label: "Notes", section: "tools", macToolId: "notes", macRoute: "databaseCollection(notes)", webSurface: "implemented" },
  { route: "calendar", label: "Calendar", section: "tools", macToolId: "calendar", macRoute: "calendarHome", webSurface: "companion" },
  { route: "contacts", label: "Contacts", section: "tools", macToolId: "contacts", macRoute: "contactsHome", webSurface: "companion" },
  { route: "projects", label: "Projects", section: "tools", macToolId: "projects", macRoute: "databaseCollection(projects)", webSurface: "implemented" },
  { route: "secrets", label: "Secrets", section: "tools", macToolId: "secrets", macRoute: "secretsHome", webSurface: "implemented" },
  { route: "memory", label: "Memory", section: "tools", macToolId: "memory", macRoute: "memoryHome", webSurface: "implemented" },
  { route: "database", label: "Database", section: "tools", macToolId: "database", macRoute: "databaseHome", webSurface: "implemented" },
  { route: "index", label: "Index", section: "tools", macToolId: "index", macRoute: "indexHome", webSurface: "companion" },
  { route: "mac-care", label: "Mac Care", section: "tools", macToolId: "macCare", macRoute: "macCare", webSurface: "companion" },
  { route: "marketplace", label: "Marketplace", section: "tools", macToolId: "marketplace", macRoute: "marketplaceHome", webSurface: "companion" },
  { route: "photos", label: "Photos", section: "tools", macToolId: "photos", macRoute: "drivePhotos", webSurface: "companion" },
  { route: "documents", label: "Documents", section: "tools", macToolId: "documents", macRoute: "driveDocuments", webSurface: "companion" },
  { route: "recent", label: "Recent", section: "tools", macToolId: "recent", macRoute: "driveRecent", webSurface: "companion" },
  { route: "drive", label: "Drive", section: "tools", macToolId: "drive", macRoute: "driveAdmin", webSurface: "companion" },
  { route: "agents", label: "Agents", section: "tools", macToolId: "agents", macRoute: "agentsHome", webSurface: "companion" },
  { route: "personalities", label: "Personalities", section: "tools", macToolId: "personalities", macRoute: "personalitiesHome", webSurface: "companion" },
  { route: "skill-collections", label: "Skill Collections", section: "tools", macToolId: "skillCollections", macRoute: "skillCollectionsHome", webSurface: "companion" },
  { route: "connections", label: "Connections", section: "tools", macToolId: "connections", macRoute: "connectionsHome", webSurface: "companion" },
  { route: "publishing", label: "Publishing", section: "tools", macToolId: "publishing", macRoute: "publishingHome", webSurface: "companion" },
];

export const RUNTIME_ROUTE_ENTRIES: RouteCatalogEntry[] = [
  { route: "pomodoro", label: "Pomodoro", section: "runtime", macRoute: "life/pomodoro", webSurface: "implemented" },
  { route: "mcp", label: "MCP", section: "runtime", macRoute: "settings/mcp", webSurface: "implemented" },
  { route: "local-models", label: "Local models", section: "runtime", macRoute: "settings/localModels", webSurface: "implemented" },
];

export const SETTINGS_ROUTE_ENTRIES: RouteCatalogEntry[] = [
  { route: "settings", label: "Settings", section: "settings", macRoute: "settings", webSurface: "implemented" },
];

export const ROUTE_CATALOG: RouteCatalogEntry[] = [
  ...PRIMARY_ROUTE_ENTRIES,
  ...MAC_SIDEBAR_TOOL_ENTRIES,
  ...RUNTIME_ROUTE_ENTRIES,
  ...SETTINGS_ROUTE_ENTRIES,
];

export function routeEntry(route: AppRoute): RouteCatalogEntry {
  const entry = ROUTE_CATALOG.find((candidate) => candidate.route === route);
  if (!entry) {
    throw new Error(`Unknown web route: ${route}`);
  }
  return entry;
}

export function routeEntries(section: RouteSectionId): RouteCatalogEntry[] {
  return ROUTE_CATALOG.filter((entry) => entry.section === section);
}
