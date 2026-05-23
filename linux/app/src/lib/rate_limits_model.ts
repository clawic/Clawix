interface RateLimitWindow {
  usedPercent?: number;
}

interface CreditsSnapshot {
  unlimited?: boolean;
  balance?: string | null;
}

export interface RateLimitSnapshot {
  primary?: RateLimitWindow | null;
  secondary?: RateLimitWindow | null;
  credits?: CreditsSnapshot | null;
}

export interface RateLimitRow {
  label: string;
  value: string;
}

export function rateLimitRows(snapshot: RateLimitSnapshot | null | undefined): RateLimitRow[] {
  if (!snapshot) return [];

  const rows: RateLimitRow[] = [];
  if (typeof snapshot.primary?.usedPercent === "number") {
    rows.push({ label: "Primary window", value: `${snapshot.primary.usedPercent}% used` });
  }
  if (typeof snapshot.secondary?.usedPercent === "number") {
    rows.push({ label: "Secondary window", value: `${snapshot.secondary.usedPercent}% used` });
  }
  if (snapshot.credits) {
    rows.push({
      label: "Credits",
      value: snapshot.credits.unlimited ? "Unlimited" : snapshot.credits.balance ?? "unknown"
    });
  }
  return rows;
}
