import { useMemo, useState } from "react";
import { IdCardIcon, PlusIcon, StarIcon } from "../../icons";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import { t } from "../../localization/i18n";
import {
  CONTACT_ACCOUNTS,
  CONTACT_GROUPS,
  CONTACTS,
  filterContacts,
  fullName,
  groupedContacts,
} from "./personal-data-model";

export function ContactsView() {
  const [query, setQuery] = useState("");
  const contacts = useMemo(() => filterContacts(CONTACTS, query), [query]);
  const groups = useMemo(() => groupedContacts(contacts), [contacts]);
  const selected = contacts[0] ?? null;

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="flex items-start gap-3 mb-4">
            <PageHeader title={t("Contacts")} subtitle={t("Accounts, groups, contacts, and selected contact detail.")} />
            <div className="flex-1" />
            <TextField value={query} onChange={(event) => setQuery(event.target.value)} placeholder={t("Search contacts")} aria-label={t("Search contacts")} className="max-w-[240px]" style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }} />
            <IconChipButton icon={<PlusIcon size={12} />} label={t("New contact")} />
          </div>

          <div className="grid gap-3 md:grid-cols-[220px_minmax(260px,320px)_1fr]">
            <Card>
              <div style={{ padding: 14 }}>
                <SectionTitle title={t("Accounts")} />
                <div className="mb-4 grid gap-1.5">
                  {CONTACT_ACCOUNTS.map((account) => (
                    <SideRow key={account.id} title={account.title} count={CONTACTS.filter((contact) => contact.accountId === account.id).length} />
                  ))}
                </div>
                <SectionTitle title={t("Groups")} />
                <div className="grid gap-1.5">
                  {CONTACT_GROUPS.map((group) => (
                    <SideRow key={group.id} title={group.title} count={CONTACTS.filter((contact) => contact.groupIds.includes(group.id)).length} smart={group.isSmart} />
                  ))}
                </div>
              </div>
            </Card>

            <Card>
              {groups.map((group, groupIndex) => (
                <div key={group.header}>
                  {groupIndex > 0 && <CardDivider />}
                  <div className="px-3 pt-3 pb-1 text-[11px] font-semibold text-[var(--color-fg-secondary)]">{group.header}</div>
                  {group.contacts.map((contact) => (
                    <div key={contact.id} className="flex items-center gap-3 px-3 py-2">
                      <Avatar contact={contact} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[12.5px] font-semibold text-[var(--color-fg)]">{fullName(contact)}</div>
                        <div className="truncate text-[11.5px] text-[var(--color-fg-secondary)]">{contact.organization ?? contact.email}</div>
                      </div>
                      {contact.isFavorite && <StarIcon size={12} className="text-[var(--color-fg-secondary)]" />}
                    </div>
                  ))}
                </div>
              ))}
            </Card>

            <Card>
              {selected ? (
                <div className="grid gap-4" style={{ padding: 18 }}>
                  <div className="flex items-center gap-3">
                    <Avatar contact={selected} large />
                    <div className="min-w-0">
                      <div className="truncate text-[18px] font-semibold text-[var(--color-fg)]">{fullName(selected)}</div>
                      <div className="truncate text-[12.5px] text-[var(--color-fg-secondary)]">{selected.jobTitle ?? t("Contact")}</div>
                    </div>
                  </div>
                  <DetailRow label={t("Email")} value={selected.email} />
                  <DetailRow label={t("Phone")} value={selected.phone} />
                  {selected.organization && <DetailRow label={t("Organization")} value={selected.organization} />}
                </div>
              ) : (
                <div className="grid h-full place-items-center p-8 text-center text-[12.5px] text-[var(--color-fg-secondary)]">
                  {t("No Contact Selected")}
                </div>
              )}
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
}

function SectionTitle({ title }: { title: string }) {
  return <div className="mb-2 text-[12px] font-semibold text-[var(--color-fg-secondary)]">{title}</div>;
}

function SideRow({ title, count, smart }: { title: string; count: number; smart?: boolean }) {
  return (
    <div className="flex items-center gap-2 rounded-md bg-white/[0.035] px-2.5 py-2">
      <IdCardIcon size={12} className="text-[var(--color-fg-secondary)]" />
      <div className="min-w-0 flex-1 truncate text-[12.5px] text-[var(--color-fg)]">{title}</div>
      {smart && <span className="text-[10px] text-[var(--color-fg-tertiary)]">{t("smart")}</span>}
      <span className="text-[11px] text-[var(--color-fg-secondary)]">{count}</span>
    </div>
  );
}

function Avatar({ contact, large }: { contact: { givenName: string; familyName: string }; large?: boolean }) {
  const initials = `${contact.givenName[0] ?? ""}${contact.familyName[0] ?? ""}`.toUpperCase();
  return (
    <div
      className="grid shrink-0 place-items-center rounded-full bg-white/[0.12] font-semibold text-[var(--color-fg)]"
      style={{ width: large ? 48 : 28, height: large ? 48 : 28, fontSize: large ? 16 : 11 }}
    >
      {initials}
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[11px] font-semibold text-[var(--color-fg-secondary)]">{label}</div>
      <div className="mt-1 text-[13px] text-[var(--color-fg)]">{value}</div>
    </div>
  );
}
