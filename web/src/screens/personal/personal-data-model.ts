export interface CalendarSource {
  id: string;
  title: string;
  color: string;
  isReadOnly: boolean;
}

export interface CalendarEventItem {
  id: string;
  title: string;
  calendarId: string;
  day: string;
  time: string;
  durationMinutes: number;
  isAllDay: boolean;
}

export interface ContactItem {
  id: string;
  givenName: string;
  familyName: string;
  organization?: string;
  jobTitle?: string;
  phone: string;
  email: string;
  groupIds: string[];
  accountId: string;
  isFavorite: boolean;
}

export interface ContactGroup {
  id: string;
  title: string;
  accountId: string;
  isSmart: boolean;
}

export interface ContactAccount {
  id: string;
  title: string;
}

export const CALENDAR_SOURCES: CalendarSource[] = [
  { id: "personal", title: "Personal", color: "#76a7ff", isReadOnly: false },
  { id: "work", title: "Work", color: "#f4a261", isReadOnly: false },
  { id: "family", title: "Family", color: "#72c17b", isReadOnly: false },
  { id: "holidays", title: "Holidays", color: "#f07178", isReadOnly: true },
];

export const CALENDAR_EVENTS: CalendarEventItem[] = [
  { id: "morning-standup", title: "Morning standup", calendarId: "work", day: "Today", time: "09:30", durationMinutes: 30, isAllDay: false },
  { id: "design-review", title: "Design review", calendarId: "work", day: "Today", time: "11:00", durationMinutes: 60, isAllDay: false },
  { id: "lunch-alex", title: "Lunch with Alex", calendarId: "personal", day: "Today", time: "13:00", durationMinutes: 75, isAllDay: false },
  { id: "focus-block", title: "Focus block", calendarId: "work", day: "Today", time: "15:00", durationMinutes: 90, isAllDay: false },
  { id: "pickup-kids", title: "Pickup kids", calendarId: "family", day: "Today", time: "17:15", durationMinutes: 30, isAllDay: false },
  { id: "holiday", title: "Holiday", calendarId: "holidays", day: "Tomorrow", time: "All day", durationMinutes: 1440, isAllDay: true },
];

export const CONTACT_ACCOUNTS: ContactAccount[] = [
  { id: "acct-personal", title: "Personal" },
  { id: "acct-work", title: "Work" },
];

export const CONTACT_GROUPS: ContactGroup[] = [
  { id: "grp-team", accountId: "acct-work", title: "Team", isSmart: false },
  { id: "grp-family", accountId: "acct-personal", title: "Family", isSmart: false },
  { id: "grp-friends", accountId: "acct-personal", title: "Friends", isSmart: false },
  { id: "smart-engineers", accountId: "acct-work", title: "Engineers", isSmart: true },
];

export const CONTACTS: ContactItem[] = [
  { id: "c-1", givenName: "Ana", familyName: "Garcia", organization: "Northwind", jobTitle: "Senior Engineer", phone: "+34 555 010 234", email: "ana.garcia@example.com", groupIds: ["grp-team"], accountId: "acct-work", isFavorite: true },
  { id: "c-2", givenName: "Bob", familyName: "Hill", phone: "+1 555 020 100", email: "bob.hill@example.com", groupIds: ["grp-friends"], accountId: "acct-personal", isFavorite: false },
  { id: "c-3", givenName: "Carol", familyName: "Martinez", organization: "Contoso", jobTitle: "Design Lead", phone: "+34 555 030 088", email: "carol.m@example.com", groupIds: ["grp-team"], accountId: "acct-work", isFavorite: false },
  { id: "c-4", givenName: "Daniel", familyName: "Owen", phone: "+1 555 040 717", email: "daniel.owen@example.com", groupIds: ["grp-family"], accountId: "acct-personal", isFavorite: true },
  { id: "c-5", givenName: "Elena", familyName: "Pereira", organization: "Northwind", jobTitle: "Junior Engineer", phone: "+34 555 050 411", email: "elena.p@example.com", groupIds: ["grp-team"], accountId: "acct-work", isFavorite: false },
  { id: "c-9", givenName: "Iris", familyName: "Tanaka", organization: "Fabrikam", jobTitle: "Engineer", phone: "+1 555 090 213", email: "iris.t@example.com", groupIds: ["grp-team"], accountId: "acct-work", isFavorite: false },
];

export function sourceForEvent(event: CalendarEventItem): CalendarSource {
  return CALENDAR_SOURCES.find((source) => source.id === event.calendarId) ?? CALENDAR_SOURCES[0]!;
}

export function filterCalendarEvents(events: CalendarEventItem[], query: string): CalendarEventItem[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return events;
  return events.filter((event) => {
    const source = sourceForEvent(event);
    return (
      event.title.toLowerCase().includes(normalized) ||
      event.day.toLowerCase().includes(normalized) ||
      source.title.toLowerCase().includes(normalized)
    );
  });
}

export function fullName(contact: ContactItem): string {
  return `${contact.givenName} ${contact.familyName}`.trim();
}

export function filterContacts(contacts: ContactItem[], query: string): ContactItem[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return contacts;
  return contacts.filter((contact) => {
    return (
      fullName(contact).toLowerCase().includes(normalized) ||
      (contact.organization ?? "").toLowerCase().includes(normalized) ||
      (contact.jobTitle ?? "").toLowerCase().includes(normalized) ||
      contact.email.toLowerCase().includes(normalized)
    );
  });
}

export function groupedContacts(contacts: ContactItem[]): Array<{ header: string; contacts: ContactItem[] }> {
  const groups = new Map<string, ContactItem[]>();
  for (const contact of contacts) {
    const header = contact.familyName.slice(0, 1).toUpperCase() || "#";
    groups.set(header, [...(groups.get(header) ?? []), contact]);
  }
  return [...groups.entries()]
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .map(([header, items]) => ({
      header,
      contacts: items.sort((lhs, rhs) => fullName(lhs).localeCompare(fullName(rhs))),
    }));
}
