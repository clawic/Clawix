import type { AppRoute } from "../sidebar/route-catalog";

export type CuratedCollectionId = "tasks" | "goals" | "notes";

export interface CollectionRecord {
  id: string;
  title: string;
  detail: string;
  status: string;
  meta: string;
}

export interface CollectionConfig {
  id: CuratedCollectionId;
  route: AppRoute;
  title: string;
  subtitle: string;
  emptyText: string;
  records: CollectionRecord[];
}

export const COLLECTION_CONFIGS: Record<CuratedCollectionId, CollectionConfig> = {
  tasks: {
    id: "tasks",
    route: "tasks",
    title: "Tasks",
    subtitle: "Curated task records from the database collection.",
    emptyText: "No tasks yet.",
    records: [
      {
        id: "task-review-inbox",
        title: "Review inbox",
        detail: "Triage new work items and decide what should become a chat, project, or reminder.",
        status: "open",
        meta: "today",
      },
      {
        id: "task-verify-bridge",
        title: "Verify bridge health",
        detail: "Check companion connectivity before running visible web flows.",
        status: "next",
        meta: "ops",
      },
    ],
  },
  goals: {
    id: "goals",
    route: "goals",
    title: "Goals",
    subtitle: "Active objectives tracked as database records.",
    emptyText: "No goals yet.",
    records: [
      {
        id: "goal-web-parity",
        title: "Web parity",
        detail: "Bring web surfaces, appearance, and tests up to macOS coverage.",
        status: "active",
        meta: "product",
      },
      {
        id: "goal-release-readiness",
        title: "Release readiness",
        detail: "Keep validation and public hygiene green before release work starts.",
        status: "tracking",
        meta: "quality",
      },
    ],
  },
  notes: {
    id: "notes",
    route: "notes",
    title: "Notes",
    subtitle: "Free-form database notes for reusable context.",
    emptyText: "No notes yet.",
    records: [
      {
        id: "note-validation",
        title: "Validation standard",
        detail: "Visible web changes need tests and a browser check when the route renders user-facing UI.",
        status: "note",
        meta: "practice",
      },
      {
        id: "note-boundaries",
        title: "Host boundary",
        detail: "Framework records live in ClawJS; the web client renders and edits only through explicit bridge surfaces.",
        status: "note",
        meta: "architecture",
      },
    ],
  },
};

export const CURATED_COLLECTION_ROUTES: AppRoute[] = ["tasks", "goals", "notes"];

export function collectionForRoute(route: AppRoute): CollectionConfig | null {
  return Object.values(COLLECTION_CONFIGS).find((collection) => collection.route === route) ?? null;
}

export function filterCollectionRecords(records: CollectionRecord[], query: string): CollectionRecord[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return records;
  return records.filter((record) => {
    return (
      record.title.toLowerCase().includes(normalized) ||
      record.detail.toLowerCase().includes(normalized) ||
      record.status.toLowerCase().includes(normalized) ||
      record.meta.toLowerCase().includes(normalized)
    );
  });
}
