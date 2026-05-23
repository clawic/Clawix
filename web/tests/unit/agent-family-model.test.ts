import { describe, expect, it } from "vitest";
import {
  AGENTS,
  CONNECTIONS,
  PERSONALITIES,
  SKILL_COLLECTIONS,
  agentFamilyConfig,
  agentFamilyCounts,
  agentsUsingConnection,
  agentsUsingPersonality,
  agentsUsingSkillCollection,
  filterAgents,
  filterConnections,
  filterPersonalities,
  filterSkillCollections,
  runtimeLabel,
} from "../../src/screens/agents/agent-family-model";

describe("agent family model", () => {
  it("maps every agent-family route to a macOS-matching title", () => {
    expect(agentFamilyConfig("agents").title).toBe("Agents");
    expect(agentFamilyConfig("personalities").title).toBe("Personalities");
    expect(agentFamilyConfig("skill-collections").title).toBe("Skill Collections");
    expect(agentFamilyConfig("connections").title).toBe("Connections");
  });

  it("counts each catalog for the shared summary", () => {
    expect(agentFamilyCounts()).toEqual({
      agents: AGENTS.length,
      personalities: PERSONALITIES.length,
      "skill-collections": SKILL_COLLECTIONS.length,
      connections: CONNECTIONS.length,
    });
  });

  it("filters agents by role, runtime, model, and autonomy", () => {
    expect(filterAgents(AGENTS, "release").map((agent) => agent.id)).toEqual(["agent.release.coordinator"]);
    expect(filterAgents(AGENTS, "codex").map((agent) => agent.id)).toEqual(["agent.default.codex"]);
    expect(filterAgents(AGENTS, "observe").map((agent) => agent.id)).toEqual(["agent.research.reader"]);
    expect(runtimeLabel("claw")).toBe("Claw");
  });

  it("filters supporting catalogs by metadata", () => {
    expect(filterPersonalities(PERSONALITIES, "evidence").map((item) => item.id)).toEqual([
      "personality.precise",
    ]);
    expect(filterSkillCollections(SKILL_COLLECTIONS, "validation").map((item) => item.id)).toEqual([
      "collection.release",
    ]);
    expect(filterConnections(CONNECTIONS, "mail").map((item) => item.id)).toEqual([
      "connection.email.digest",
    ]);
  });

  it("resolves reverse usage for detail panes", () => {
    expect(agentsUsingPersonality("personality.precise").map((agent) => agent.id)).toEqual([
      "agent.release.coordinator",
    ]);
    expect(agentsUsingSkillCollection("collection.code").map((agent) => agent.id)).toEqual([
      "agent.default.codex",
      "agent.release.coordinator",
    ]);
    expect(agentsUsingConnection("connection.webhook.status").map((agent) => agent.id)).toEqual([
      "agent.release.coordinator",
    ]);
  });
});
