import { describe, expect, it } from "vitest";
import {
  AUTOMATION_TEMPLATE_SECTIONS,
  DEFAULT_AUTOMATIONS,
  automationGroups,
  setAutomationEnabled,
  templateCardCount,
} from "../../src/screens/automations/automation-model";

describe("automation model", () => {
  it("groups current and paused automations like macOS", () => {
    const groups = automationGroups(DEFAULT_AUTOMATIONS);

    expect(groups.current.map((item) => item.id)).toEqual(["pr-review"]);
    expect(groups.paused.map((item) => item.id)).toEqual(["auto-run-tests"]);
  });

  it("caps each automation group at fifty rows", () => {
    const items = Array.from({ length: 55 }, (_, index) => ({
      ...DEFAULT_AUTOMATIONS[0]!,
      id: `automation-${index}`,
    }));

    expect(automationGroups(items).current).toHaveLength(50);
  });

  it("toggles persisted automation state and preserves template coverage", () => {
    const updated = setAutomationEnabled(DEFAULT_AUTOMATIONS, "auto-run-tests", true);

    expect(updated.find((item) => item.id === "auto-run-tests")?.isEnabled).toBe(true);
    expect(AUTOMATION_TEMPLATE_SECTIONS.map((section) => section.title)).toEqual([
      "Status reports",
      "Release prep",
      "Incidents & triage",
    ]);
    expect(templateCardCount(AUTOMATION_TEMPLATE_SECTIONS)).toBe(9);
  });
});
