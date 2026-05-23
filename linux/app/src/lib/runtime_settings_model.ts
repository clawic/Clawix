export type RuntimeSurfaceId = "runtimeAdapter" | "localModels";

export interface RuntimeStatusRow {
  label: string;
  value: string;
  detail: string;
}

export interface RuntimeSurface {
  id: RuntimeSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  rows: RuntimeStatusRow[];
}

export const runtimeSettingsSurfaces: RuntimeSurface[] = [
  {
    id: "runtimeAdapter",
    title: "Runtime adapter",
    detail: "Framework-owned adapter selection with host policy enforcement.",
    storageOwner: "framework-runtime",
    validation: "Runtime adapter registry tests",
    rows: [
      {
        label: "Startup",
        value: "metadata only",
        detail: "Opening Settings does not start an adapter process."
      },
      {
        label: "Selection",
        value: "framework",
        detail: "Selection persists through framework runtime configuration or host policy."
      },
      {
        label: "Visibility",
        value: "feature gated",
        detail: "Hidden adapters stay unavailable until the framework registry marks them visible."
      }
    ]
  },
  {
    id: "localModels",
    title: "Local models",
    detail: "Host-local binaries and model cache surfaced through framework capabilities.",
    storageOwner: "host-cache-plus-framework-capability",
    validation: "Capability tests and no synced model blob guard",
    rows: [
      {
        label: "Availability",
        value: "capability records",
        detail: "Linux reports model availability as capability metadata, not synced blobs."
      },
      {
        label: "Binaries",
        value: "host local",
        detail: "Model runtimes and weights remain local to the Linux host cache."
      },
      {
        label: "Selection",
        value: "policy gated",
        detail: "Model choices must respect framework capability and host policy records."
      }
    ]
  }
];

export function runtimeSurfaceById(id: RuntimeSurfaceId): RuntimeSurface {
  return runtimeSettingsSurfaces.find((surface) => surface.id === id) ?? runtimeSettingsSurfaces[0];
}

export function runtimeStatusRowCount(): number {
  return runtimeSettingsSurfaces.reduce((count, surface) => count + surface.rows.length, 0);
}
