import { describe, expect, it } from "vitest";
import {
  allSkillTags,
  createLocalSkill,
  DEFAULT_SKILLS,
  filterSkills,
  mergeSkills,
  setSkillActive,
} from "../../src/screens/skills/skill-model";

describe("skill model", () => {
  it("keeps the macOS seed catalog sorted through filters", () => {
    const filtered = filterSkills(DEFAULT_SKILLS, { query: "", kind: "procedure", tag: null });

    expect(filtered.map((skill) => skill.slug)).toEqual(["code-review", "email-writing"]);
  });

  it("filters by search text and tags", () => {
    expect(filterSkills(DEFAULT_SKILLS, { query: "root causes", kind: null, tag: null }).map((skill) => skill.slug)).toEqual([
      "engineer-rigorous",
    ]);
    expect(filterSkills(DEFAULT_SKILLS, { query: "", kind: null, tag: "infra" }).map((skill) => skill.slug)).toEqual([
      "devops-edge-specialist",
      "edge-network-ops",
    ]);
  });

  it("sorts tags by frequency and merges local skills by slug", () => {
    const local = createLocalSkill({
      name: "Incident Brief",
      description: "Summarize an incident",
      kind: "procedure",
      tags: "engineering, incident",
    });

    expect(local?.slug).toBe("incident-brief");
    const merged = mergeSkills(local ? [local] : []);

    expect(merged.some((skill) => skill.slug === "incident-brief")).toBe(true);
    expect(allSkillTags(merged)[0]).toBe("engineering");
  });

  it("overrides persisted activation by skill slug", () => {
    const state = setSkillActive({}, "code-review", true);

    expect(state["code-review"]).toBe(true);
  });
});
