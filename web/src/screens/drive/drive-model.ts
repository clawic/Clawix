export type DriveViewId = "drive" | "photos" | "documents" | "recent";

export type DriveItemKind = "folder" | "image" | "document" | "archive";

export interface DriveItem {
  id: string;
  name: string;
  kind: DriveItemKind;
  mimeType: string;
  sizeLabel: string;
  modifiedRank: number;
  modifiedLabel: string;
  parentLabel: string;
  starred: boolean;
  shared: boolean;
  trashed: boolean;
}

export interface DriveViewConfig {
  title: string;
  subtitle: string;
  searchPlaceholder: string;
  emptyText: string;
  prefersGrid: boolean;
}

export const DRIVE_ITEMS: DriveItem[] = [
  {
    id: "folder-design-references",
    name: "Design references",
    kind: "folder",
    mimeType: "folder",
    sizeLabel: "12 items",
    modifiedRank: 4,
    modifiedLabel: "Today 09:42",
    parentLabel: "Drive",
    starred: true,
    shared: true,
    trashed: false,
  },
  {
    id: "folder-release-notes",
    name: "Release notes",
    kind: "folder",
    mimeType: "folder",
    sizeLabel: "8 items",
    modifiedRank: 8,
    modifiedLabel: "Yesterday 18:15",
    parentLabel: "Drive",
    starred: false,
    shared: false,
    trashed: false,
  },
  {
    id: "image-calendar-preview",
    name: "calendar-preview.png",
    kind: "image",
    mimeType: "image/png",
    sizeLabel: "1.8 MB",
    modifiedRank: 1,
    modifiedLabel: "Today 11:24",
    parentLabel: "Design references",
    starred: true,
    shared: false,
    trashed: false,
  },
  {
    id: "image-contact-grid",
    name: "contact-grid.png",
    kind: "image",
    mimeType: "image/png",
    sizeLabel: "2.4 MB",
    modifiedRank: 5,
    modifiedLabel: "Today 08:07",
    parentLabel: "Design references",
    starred: false,
    shared: true,
    trashed: false,
  },
  {
    id: "document-launch-checklist",
    name: "launch-checklist.md",
    kind: "document",
    mimeType: "text/markdown",
    sizeLabel: "38 KB",
    modifiedRank: 2,
    modifiedLabel: "Today 10:58",
    parentLabel: "Release notes",
    starred: true,
    shared: true,
    trashed: false,
  },
  {
    id: "document-weekly-summary",
    name: "weekly-summary.pdf",
    kind: "document",
    mimeType: "application/pdf",
    sizeLabel: "612 KB",
    modifiedRank: 3,
    modifiedLabel: "Today 10:12",
    parentLabel: "Drive",
    starred: false,
    shared: false,
    trashed: false,
  },
  {
    id: "archive-drive-contract",
    name: "drive-contract.zip",
    kind: "archive",
    mimeType: "application/zip",
    sizeLabel: "4.7 MB",
    modifiedRank: 7,
    modifiedLabel: "Yesterday 20:34",
    parentLabel: "Drive",
    starred: false,
    shared: false,
    trashed: false,
  },
  {
    id: "document-trashed-draft",
    name: "discarded-draft.txt",
    kind: "document",
    mimeType: "text/plain",
    sizeLabel: "9 KB",
    modifiedRank: 6,
    modifiedLabel: "Yesterday 21:10",
    parentLabel: "Trash",
    starred: false,
    shared: false,
    trashed: true,
  },
];

export function driveViewConfig(view: DriveViewId): DriveViewConfig {
  switch (view) {
    case "photos":
      return {
        title: "Photos",
        subtitle: "Image files from the Drive library.",
        searchPlaceholder: "Search photos",
        emptyText: "No photos match",
        prefersGrid: true,
      };
    case "documents":
      return {
        title: "Documents",
        subtitle: "Text, PDF, and working documents.",
        searchPlaceholder: "Search documents",
        emptyText: "No documents match",
        prefersGrid: false,
      };
    case "recent":
      return {
        title: "Recent",
        subtitle: "Files sorted by latest activity.",
        searchPlaceholder: "Search recent files",
        emptyText: "No recent files match",
        prefersGrid: false,
      };
    case "drive":
      return {
        title: "Drive",
        subtitle: "Browse the local Drive surface.",
        searchPlaceholder: "Search files",
        emptyText: "No files match",
        prefersGrid: false,
      };
  }
}

export function driveItemsForView(view: DriveViewId, items: DriveItem[] = DRIVE_ITEMS): DriveItem[] {
  const liveItems = items.filter((item) => !item.trashed);
  switch (view) {
    case "photos":
      return liveItems.filter((item) => item.kind === "image");
    case "documents":
      return liveItems.filter((item) => item.kind === "document");
    case "recent":
      return [...liveItems].sort((lhs, rhs) => lhs.modifiedRank - rhs.modifiedRank);
    case "drive":
      return liveItems;
  }
}

export function filterDriveItems(items: DriveItem[], query: string): DriveItem[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return items;
  return items.filter((item) => {
    return (
      item.name.toLowerCase().includes(normalized) ||
      item.kind.toLowerCase().includes(normalized) ||
      item.mimeType.toLowerCase().includes(normalized) ||
      item.parentLabel.toLowerCase().includes(normalized)
    );
  });
}

export function driveItemCounts(items: DriveItem[] = DRIVE_ITEMS) {
  const liveItems = items.filter((item) => !item.trashed);
  return {
    drive: liveItems.length,
    photos: liveItems.filter((item) => item.kind === "image").length,
    documents: liveItems.filter((item) => item.kind === "document").length,
    recent: liveItems.length,
  } satisfies Record<DriveViewId, number>;
}
