import type { WireMessage, WireSession } from "../../bridge/wire";

export type SearchResultKind = "chat" | "message";

export interface SearchResult {
  id: string;
  sessionId: string;
  kind: SearchResultKind;
  title: string;
  snippet: string;
  meta: string;
  rank: number;
}

interface SearchInput {
  sessions: WireSession[];
  messagesBySession: Record<string, WireMessage[]>;
  query: string;
}

export function searchConversations({
  sessions,
  messagesBySession,
  query,
}: SearchInput): SearchResult[] {
  const terms = normalizedTerms(query);
  if (terms.length === 0) return [];

  const out: SearchResult[] = [];
  const seen = new Set<string>();

  for (const session of sessions) {
    const title = session.title.trim() || "Untitled";
    const haystack = [
      title,
      session.lastMessagePreview ?? "",
      session.cwd ?? "",
      session.branch ?? "",
      session.agent ?? "",
    ].join("\n");

    if (matchesAll(haystack, terms)) {
      pushUnique(out, seen, {
        id: `chat:${session.id}`,
        sessionId: session.id,
        kind: "chat",
        title,
        snippet: session.lastMessagePreview || session.cwd || "Open conversation",
        meta: sessionMeta(session),
        rank: session.isPinned ? 120 : 100,
      });
    }

    for (const message of messagesBySession[session.id] ?? []) {
      const messageText = [
        message.content,
        message.reasoningText,
        ...message.timeline.map((entry) => (entry.type === "tools" ? "" : entry.text)),
      ].join("\n");
      if (!matchesAll(messageText, terms)) continue;

      pushUnique(out, seen, {
        id: `message:${session.id}:${message.id}`,
        sessionId: session.id,
        kind: "message",
        title,
        snippet: excerpt(messageText, terms[0] ?? ""),
        meta: message.role === "assistant" ? "Assistant message" : "User message",
        rank: 70,
      });
    }
  }

  return out.sort((a, b) => b.rank - a.rank || a.title.localeCompare(b.title));
}

function normalizedTerms(query: string): string[] {
  return query
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean);
}

function matchesAll(value: string, terms: string[]): boolean {
  const haystack = value.toLowerCase();
  return terms.every((term) => haystack.includes(term));
}

function pushUnique(out: SearchResult[], seen: Set<string>, result: SearchResult): void {
  if (seen.has(result.id)) return;
  seen.add(result.id);
  out.push(result);
}

function sessionMeta(session: WireSession): string {
  if (session.branch && session.cwd) return `${session.branch} - ${session.cwd}`;
  return session.branch || session.cwd || (session.isArchived ? "Archived chat" : "Chat");
}

function excerpt(value: string, term: string): string {
  const compact = value.replace(/\s+/g, " ").trim();
  if (!compact) return "Message match";
  if (!term) return compact.slice(0, 160);

  const index = compact.toLowerCase().indexOf(term.toLowerCase());
  if (index < 0) return compact.slice(0, 160);

  const start = Math.max(0, index - 56);
  const end = Math.min(compact.length, index + term.length + 96);
  const prefix = start > 0 ? "..." : "";
  const suffix = end < compact.length ? "..." : "";
  return `${prefix}${compact.slice(start, end)}${suffix}`;
}
