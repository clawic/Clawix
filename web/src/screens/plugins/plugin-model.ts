export interface PluginDefinition {
  id: string;
  name: string;
  description: string;
  iconName: "globe" | "terminal" | "search";
  defaultEnabled: boolean;
}

export interface PluginItem extends PluginDefinition {
  isEnabled: boolean;
}

export const DEFAULT_PLUGINS: PluginDefinition[] = [
  {
    id: "repository",
    name: "Repository",
    description: "Integration with code repositories",
    iconName: "globe",
    defaultEnabled: true,
  },
  {
    id: "terminal",
    name: "Terminal",
    description: "Access to the system terminal",
    iconName: "terminal",
    defaultEnabled: true,
  },
  {
    id: "web-search",
    name: "Web search",
    description: "Search the web for information",
    iconName: "search",
    defaultEnabled: false,
  },
];

export type PluginEnabledState = Record<string, boolean>;

export function pluginItems(enabledState: PluginEnabledState): PluginItem[] {
  return DEFAULT_PLUGINS.map((plugin) => ({
    ...plugin,
    isEnabled: enabledState[plugin.id] ?? plugin.defaultEnabled,
  }));
}

export function filterPlugins(plugins: PluginItem[], query: string): PluginItem[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return plugins;
  return plugins.filter((plugin) =>
    plugin.name.toLowerCase().includes(normalized) ||
    plugin.description.toLowerCase().includes(normalized),
  );
}

export function setPluginEnabled(
  enabledState: PluginEnabledState,
  pluginId: string,
  enabled: boolean,
): PluginEnabledState {
  return { ...enabledState, [pluginId]: enabled };
}
