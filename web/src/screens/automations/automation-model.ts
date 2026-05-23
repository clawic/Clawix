export interface AutomationItem {
  id: string;
  name: string;
  description: string;
  isEnabled: boolean;
  trigger: string;
}

export interface AutomationTemplateCard {
  id: string;
  icon: "message" | "document" | "square" | "book" | "check" | "edit" | "globe" | "tray" | "sparkle";
  tone: string;
  text: string;
}

export interface AutomationTemplateSection {
  id: string;
  title: string;
  cards: AutomationTemplateCard[];
  tallCards: boolean;
}

export const DEFAULT_AUTOMATIONS: AutomationItem[] = [
  {
    id: "pr-review",
    name: "PR review",
    description: "Review pull requests automatically",
    isEnabled: true,
    trigger: "When a PR is opened",
  },
  {
    id: "auto-run-tests",
    name: "Auto-run tests",
    description: "Run tests on every save",
    isEnabled: false,
    trigger: "On file save",
  },
];

export const AUTOMATION_TEMPLATE_SECTIONS: AutomationTemplateSection[] = [
  {
    id: "status-reports",
    title: "Status reports",
    tallCards: false,
    cards: [
      {
        id: "standup-notes",
        icon: "message",
        tone: "violet",
        text: "Wrap up yesterday's git activity into standup notes.",
      },
      {
        id: "weekly-digest",
        icon: "document",
        tone: "mint",
        text: "Roll this week's PRs, deploys, incidents and reviews into a digest.",
      },
      {
        id: "teammate-risk",
        icon: "square",
        tone: "neutral",
        text: "Group last week's PRs by teammate and topic; call out risks.",
      },
    ],
  },
  {
    id: "release-prep",
    title: "Release prep",
    tallCards: true,
    cards: [
      {
        id: "release-notes",
        icon: "book",
        tone: "coral",
        text: "Write the weekly release notes from merged PRs, with links where available.",
      },
      {
        id: "pretag-check",
        icon: "check",
        tone: "green",
        text: "Before tagging, double-check the changelog, migrations, feature flags and tests.",
      },
      {
        id: "changelog-refresh",
        icon: "edit",
        tone: "amber",
        text: "Refresh the changelog with this week's highlights and the relevant PR links.",
      },
    ],
  },
  {
    id: "incidents-triage",
    title: "Incidents & triage",
    tallCards: true,
    cards: [
      {
        id: "ci-failures",
        icon: "globe",
        tone: "teal",
        text: "Round up CI failures and flaky tests from the last window and propose the top fixes.",
      },
      {
        id: "triage-buckets",
        icon: "tray",
        tone: "neutral",
        text: "Triage CI failures by grouping them by likely root cause, and propose a minimal fix per bucket.",
      },
      {
        id: "error-clusters",
        icon: "sparkle",
        tone: "blue",
        text: "Group recent errors into clusters by pattern and stage a follow-up summary.",
      },
    ],
  },
];

export type AutomationGroups = {
  current: AutomationItem[];
  paused: AutomationItem[];
};

export function automationGroups(items: AutomationItem[]): AutomationGroups {
  return {
    current: items.filter((item) => item.isEnabled).slice(0, 50),
    paused: items.filter((item) => !item.isEnabled).slice(0, 50),
  };
}

export function setAutomationEnabled(
  items: AutomationItem[],
  automationId: string,
  isEnabled: boolean,
): AutomationItem[] {
  return items.map((item) => (item.id === automationId ? { ...item, isEnabled } : item));
}

export function templateCardCount(sections: AutomationTemplateSection[]): number {
  return sections.reduce((total, section) => total + section.cards.length, 0);
}
