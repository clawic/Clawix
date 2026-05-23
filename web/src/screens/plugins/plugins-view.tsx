import { useMemo, useState } from "react";
import { Card, PageHeader, TextField } from "../../components/ui";
import { GlobeIcon, SearchIcon, TerminalIcon } from "../../icons";
import { storage, StorageKeys } from "../../lib/storage";
import { t } from "../../localization/i18n";
import {
  filterPlugins,
  pluginItems,
  setPluginEnabled,
  type PluginEnabledState,
  type PluginItem,
} from "./plugin-model";
import { PillToggle } from "../../components/ui/pill-toggle";

export function PluginsView() {
  const [query, setQuery] = useState("");
  const [enabledState, setEnabledState] = useState<PluginEnabledState>(
    () => storage.get<PluginEnabledState>(StorageKeys.pluginEnabledState) ?? {},
  );
  const plugins = useMemo(() => filterPlugins(pluginItems(enabledState), query), [enabledState, query]);

  function toggle(pluginId: string, enabled: boolean) {
    setEnabledState((current) => {
      const next = setPluginEnabled(current, pluginId, enabled);
      storage.set(StorageKeys.pluginEnabledState, next);
      return next;
    });
  }

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[760px] mx-auto pt-8 pb-12 px-6">
          <PageHeader title={t("Plugins")} />
          <TextField
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t("Search plugins")}
            aria-label={t("Search plugins")}
            className="mb-3"
            style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
          />

          <div className="grid gap-[7px]">
            {plugins.map((plugin) => (
              <PluginRow key={plugin.id} plugin={plugin} onToggle={toggle} />
            ))}
            {plugins.length === 0 && (
              <div className="py-12 text-center text-[12.5px] text-[var(--color-fg-tertiary)]">
                {t("No plugins match")}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function PluginRow({
  plugin,
  onToggle,
}: {
  plugin: PluginItem;
  onToggle: (pluginId: string, enabled: boolean) => void;
}) {
  const Icon = plugin.iconName === "terminal" ? TerminalIcon : plugin.iconName === "search" ? SearchIcon : GlobeIcon;
  return (
    <Card>
      <div className="flex items-center gap-3.5" style={{ padding: "12px 16px" }}>
        <div
          className="grid place-items-center shrink-0"
          style={{ width: 36, height: 36, borderRadius: 8, background: "var(--color-card)" }}
        >
          <Icon size={13} className="text-[var(--color-fg-secondary)]" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="truncate" style={{ fontSize: 13, fontVariationSettings: '"wght" 700' }}>
            {t(plugin.name)}
          </div>
          <div
            className="truncate"
            style={{ fontSize: 12, color: "var(--color-fg-tertiary)", lineHeight: 1.45 }}
          >
            {t(plugin.description)}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-[11px] text-[var(--color-fg-secondary)]">
            {plugin.isEnabled ? t("Enabled") : t("Disabled")}
          </span>
          <PillToggle
            isOn={plugin.isEnabled}
            onChange={(next) => onToggle(plugin.id, next)}
          />
        </div>
      </div>
    </Card>
  );
}
