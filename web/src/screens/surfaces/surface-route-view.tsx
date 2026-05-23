import { PageHeader, Card } from "../../components/ui";
import type { RouteCatalogEntry } from "../sidebar/route-catalog";

interface Props {
  entry: RouteCatalogEntry;
}

export function SurfaceRouteView({ entry }: Props) {
  const status =
    entry.webSurface === "implemented"
      ? "Implemented web surface"
      : entry.webSurface === "companion"
        ? "Web companion surface"
        : "Parity pending";

  return (
    <div className="h-full flex flex-col">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[760px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title={entry.label} subtitle={status} />
          <div className="grid gap-3">
            <Card>
              <div className="space-y-2" style={{ padding: 16 }}>
                <div style={{ fontSize: 14, fontVariationSettings: '"wght" 800' }}>
                  macOS route
                </div>
                <div
                  className="font-mono"
                  style={{ fontSize: 12.5, color: "var(--color-fg-secondary)" }}
                >
                  {entry.macRoute}
                </div>
              </div>
            </Card>
            <Card>
              <div className="space-y-2" style={{ padding: 16 }}>
                <div style={{ fontSize: 14, fontVariationSettings: '"wght" 800' }}>
                  Web parity status
                </div>
                <p
                  style={{
                    fontSize: 12.5,
                    color: "var(--color-fg-secondary)",
                    lineHeight: 1.55,
                  }}
                >
                  This route is now addressable from the web shell and tracked in the same sidebar
                  catalog as macOS. Feature work can land behind this surface without changing the
                  route contract.
                </p>
              </div>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}
