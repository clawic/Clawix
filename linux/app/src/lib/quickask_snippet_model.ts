export type QuickAskSnippetKind = "quickask_slash" | "quickask_mention";

export interface QuickAskSnippet {
  id: string;
  kind: QuickAskSnippetKind;
  trigger: string;
  title: string;
  detail: string;
  insertion: string;
}

export const quickAskSnippetSurface = {
  id: "quickAsk.snippets",
  storageOwner: "framework-snippets",
  validation: "Snippet migration tests; QuickAsk host prefs remain local",
  commands: ["claw snippets list --json", "claw snippets upsert <slug> --json", "claw snippets delete <slug> --json"]
} as const;

export const builtInQuickAskSnippets: QuickAskSnippet[] = [
  {
    id: "slash-search",
    kind: "quickask_slash",
    trigger: "/search",
    title: "/search",
    detail: "Search the web",
    insertion: "/search "
  },
  {
    id: "slash-research",
    kind: "quickask_slash",
    trigger: "/research",
    title: "/research",
    detail: "Deep research turn",
    insertion: "/research "
  },
  {
    id: "slash-imagine",
    kind: "quickask_slash",
    trigger: "/imagine",
    title: "/imagine",
    detail: "Generate an image",
    insertion: "/imagine "
  },
  {
    id: "slash-think",
    kind: "quickask_slash",
    trigger: "/think",
    title: "/think",
    detail: "Reasoning-heavy turn",
    insertion: "/think "
  },
  {
    id: "mention-review",
    kind: "quickask_mention",
    trigger: "@review",
    title: "@review",
    detail: "Recall a saved review prompt",
    insertion: "Review the current context: "
  }
];

export function quickAskSnippetFragment(text: string): { kind: QuickAskSnippetKind; fragment: string; start: number } | null {
  const slashStart = text.lastIndexOf("/");
  const mentionStart = text.lastIndexOf("@");
  const start = Math.max(slashStart, mentionStart);
  if (start < 0) return null;

  const prefix = text.slice(0, start);
  if (prefix.length > 0 && !/\s$/.test(prefix)) return null;

  const fragment = text.slice(start).trim();
  if (fragment.includes(" ")) return null;

  return {
    kind: text[start] === "/" ? "quickask_slash" : "quickask_mention",
    fragment,
    start
  };
}

export function quickAskSnippetSuggestions(text: string, limit = 8): QuickAskSnippet[] {
  const active = quickAskSnippetFragment(text);
  if (!active) return [];

  const query = active.fragment.toLowerCase();
  return builtInQuickAskSnippets
    .filter((snippet) => snippet.kind === active.kind && snippet.trigger.toLowerCase().startsWith(query))
    .slice(0, Math.max(0, limit));
}

export function applyQuickAskSnippet(text: string, snippet: QuickAskSnippet): string {
  const active = quickAskSnippetFragment(text);
  if (!active) return text;
  return `${text.slice(0, active.start)}${snippet.insertion}`;
}
