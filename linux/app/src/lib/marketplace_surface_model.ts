export type MarketplaceSurfaceId = "marketplace" | "iotHome" | "life";

export interface MarketplaceSurface {
  id: MarketplaceSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const marketplaceSurfaces: MarketplaceSurface[] = [
  {
    id: "marketplace",
    title: "Marketplace",
    detail: "Offers, wants, prospects, receipts, and marketplace identity stay in framework storage.",
    storageOwner: "framework-marketplace",
    validation: "Marketplace contract fixtures; payment/live installs EXTERNAL PENDING without explicit approval",
    commands: ["claw marketplace choice --json", "marketplace identity APIs", "marketplace profile APIs", "marketplace vertical APIs"]
  },
  {
    id: "iotHome",
    title: "Home and IoT",
    detail: "Devices, scenes, state, and approvals route through framework IoT plus host policy.",
    storageOwner: "framework-iot-plus-host-policy",
    validation: "IoT contract fixtures; physical devices EXTERNAL PENDING",
    commands: ["claw iot homes --json", "claw iot things --json", "claw iot state --json", "claw iot approvals --json"]
  },
  {
    id: "life",
    title: "Life",
    detail: "Vertical signals use the framework signal resource registry and runtime contracts.",
    storageOwner: "framework-resource-registry",
    validation: "Life/signal fixtures; native/provider adapters EXTERNAL PENDING",
    commands: ["claw signals catalog --json", "claw signals seed-catalog --json", "claw signals observe --json", "claw signals list --json"]
  }
];

export function marketplaceSurfaceById(id: MarketplaceSurfaceId): MarketplaceSurface {
  return marketplaceSurfaces.find((surface) => surface.id === id) ?? marketplaceSurfaces[0];
}

export function marketplaceCommandCount(): number {
  return marketplaceSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
