import { describe, expect, it } from "vitest";
import {
  CALENDAR_EVENTS,
  CONTACTS,
  filterCalendarEvents,
  filterContacts,
  fullName,
  groupedContacts,
  sourceForEvent,
} from "../../src/screens/personal/personal-data-model";

describe("personal data model", () => {
  it("filters calendar events by title and source", () => {
    expect(filterCalendarEvents(CALENDAR_EVENTS, "standup").map((event) => event.id)).toEqual(["morning-standup"]);
    expect(filterCalendarEvents(CALENDAR_EVENTS, "family").map((event) => event.id)).toEqual(["pickup-kids"]);
    expect(sourceForEvent(CALENDAR_EVENTS[0]!).title).toBe("Work");
  });

  it("filters contacts by name, organization, role, and email", () => {
    expect(filterContacts(CONTACTS, "northwind").map((contact) => contact.id)).toEqual(["c-1", "c-5"]);
    expect(filterContacts(CONTACTS, "engineer").map((contact) => contact.id)).toEqual(["c-1", "c-5", "c-9"]);
    expect(fullName(CONTACTS[0]!)).toBe("Ana Garcia");
  });

  it("groups contacts by family-name initial", () => {
    const groups = groupedContacts(CONTACTS);

    expect(groups[0]?.header).toBe("G");
    expect(groups.some((group) => group.header === "T")).toBe(true);
  });
});
