import { describe, expect, it } from "vitest";
import {
  applyQuickAskSnippet,
  quickAskSnippetFragment,
  quickAskSnippetSuggestions,
  quickAskSnippetSurface
} from "./quickask_snippet_model";

describe("quickask snippet model", () => {
  it("keeps the framework-owned snippet contract explicit", () => {
    expect(quickAskSnippetSurface.id).toBe("quickAsk.snippets");
    expect(quickAskSnippetSurface.storageOwner).toBe("framework-snippets");
    expect(quickAskSnippetSurface.commands).toEqual([
      "claw snippets list --json",
      "claw snippets upsert <slug> --json",
      "claw snippets delete <slug> --json"
    ]);
    expect(quickAskSnippetSurface.validation).toContain("QuickAsk host prefs remain local");
  });

  it("finds slash and mention fragments only at token boundaries", () => {
    expect(quickAskSnippetFragment("/se")).toEqual({ kind: "quickask_slash", fragment: "/se", start: 0 });
    expect(quickAskSnippetFragment("please @rev")).toEqual({ kind: "quickask_mention", fragment: "@rev", start: 7 });
    expect(quickAskSnippetFragment("http://example.test")).toBeNull();
    expect(quickAskSnippetFragment("/search web")).toBeNull();
  });

  it("filters and applies built-in QuickAsk completions", () => {
    const slash = quickAskSnippetSuggestions("/re");
    expect(slash.map((snippet) => snippet.trigger)).toEqual(["/research"]);
    expect(applyQuickAskSnippet("/re", slash[0])).toBe("/research ");

    const mention = quickAskSnippetSuggestions("use @rev");
    expect(mention.map((snippet) => snippet.trigger)).toEqual(["@review"]);
    expect(applyQuickAskSnippet("use @rev", mention[0])).toBe("use Review the current context: ");
  });
});
