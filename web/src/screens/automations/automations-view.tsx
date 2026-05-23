import { useMemo, useState } from "react";
import {
  BadgeCheckIcon,
  FileTextIcon,
  GlobeLucideIcon,
  InboxIcon,
  MessageCircleIcon,
  SquareIcon,
  StarIcon,
  Undo2Icon,
} from "../../icons";
import { Card, PageHeader, PillToggle } from "../../components/ui";
import { storage, StorageKeys } from "../../lib/storage";
import { t } from "../../localization/i18n";
import {
  AUTOMATION_TEMPLATE_SECTIONS,
  DEFAULT_AUTOMATIONS,
  automationGroups,
  setAutomationEnabled,
  type AutomationItem,
  type AutomationTemplateCard,
} from "./automation-model";

export function AutomationsView() {
  const [automations, setAutomations] = useState<AutomationItem[]>(
    () => storage.get<AutomationItem[]>(StorageKeys.automationsCatalog) ?? DEFAULT_AUTOMATIONS,
  );
  const groups = useMemo(() => automationGroups(automations), [automations]);

  function toggle(automationId: string, isEnabled: boolean) {
    setAutomations((current) => {
      const next = setAutomationEnabled(current, automationId, isEnabled);
      storage.set(StorageKeys.automationsCatalog, next);
      return next;
    });
  }

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[760px] mx-auto pt-[73px] pb-10 px-6">
          <PageHeader
            title={t("Automations")}
            subtitle={t("Schedule recurring chats so routine work runs on its own.")}
          />

          {automations.length > 0 && (
            <div className="grid gap-[22px] mb-11">
              {groups.current.length > 0 && (
                <AutomationGroup title={t("Current")} items={groups.current} onToggle={toggle} />
              )}
              {groups.paused.length > 0 && (
                <AutomationGroup title={t("Paused")} items={groups.paused} onToggle={toggle} />
              )}
            </div>
          )}

          <div className="grid gap-[58px]">
            {AUTOMATION_TEMPLATE_SECTIONS.map((section) => (
              <section key={section.id}>
                <div className="mb-[13px] text-[12px] font-semibold text-[var(--color-fg-secondary)]">
                  {t(section.title)}
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  {section.cards.map((card) => (
                    <TemplateCard key={card.id} card={card} tall={section.tallCards} />
                  ))}
                </div>
              </section>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function AutomationGroup({
  title,
  items,
  onToggle,
}: {
  title: string;
  items: AutomationItem[];
  onToggle: (automationId: string, isEnabled: boolean) => void;
}) {
  return (
    <section>
      <div className="mb-2 text-[13.5px] font-semibold text-[var(--color-fg-secondary)]">{title}</div>
      <div className="grid gap-2">
        {items.map((automation) => (
          <Card key={automation.id}>
            <div className="flex items-center gap-3" style={{ padding: "12px 16px" }}>
              <span
                className="shrink-0 rounded-full"
                style={{
                  width: 7,
                  height: 7,
                  background: automation.isEnabled ? "var(--color-accent)" : "rgba(255,255,255,0.25)",
                }}
              />
              <div className="min-w-0 flex-1">
                <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{automation.name}</div>
                {automation.description && (
                  <div className="truncate text-[12px] text-[var(--color-fg-tertiary)]">{automation.description}</div>
                )}
              </div>
              <div className="max-w-[190px] truncate font-mono text-[11px] text-[var(--color-fg-secondary)]">
                {automation.trigger}
              </div>
              <PillToggle isOn={automation.isEnabled} onChange={(next) => onToggle(automation.id, next)} />
            </div>
          </Card>
        ))}
      </div>
    </section>
  );
}

function TemplateCard({ card, tall }: { card: AutomationTemplateCard; tall: boolean }) {
  const Icon = iconFor(card.icon);
  return (
    <Card>
      <div className="grid gap-3" style={{ minHeight: tall ? 116 : 96, padding: "14px 16px" }}>
        <Icon size={14} className={toneClass(card.tone)} />
        <div className="text-[12px] font-bold leading-[1.5] text-[var(--color-fg)]">{t(card.text)}</div>
      </div>
    </Card>
  );
}

function iconFor(icon: AutomationTemplateCard["icon"]) {
  switch (icon) {
    case "message": return MessageCircleIcon;
    case "document": return FileTextIcon;
    case "book": return FileTextIcon;
    case "check": return BadgeCheckIcon;
    case "edit": return Undo2Icon;
    case "globe": return GlobeLucideIcon;
    case "tray": return InboxIcon;
    case "sparkle": return StarIcon;
    case "square":
    default:
      return SquareIcon;
  }
}

function toneClass(tone: string): string {
  switch (tone) {
    case "violet": return "text-violet-300";
    case "mint": return "text-emerald-200";
    case "coral": return "text-red-300";
    case "green": return "text-green-300";
    case "amber": return "text-amber-300";
    case "teal": return "text-teal-300";
    case "blue": return "text-blue-300";
    default:
      return "text-[var(--color-fg-secondary)]";
  }
}
