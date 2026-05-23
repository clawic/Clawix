import { describe, expect, it } from "vitest";
import { filterPlugins, pluginItems, setPluginEnabled } from "../../src/screens/plugins/plugin-model";

describe("plugin model", () => {
  it("uses macOS default plugin state", () => {
    const plugins = pluginItems({});

    expect(plugins.map((plugin) => [plugin.id, plugin.isEnabled])).toEqual([
      ["repository", true],
      ["terminal", true],
      ["web-search", false],
    ]);
  });

  it("filters by name and description", () => {
    const plugins = pluginItems({});

    expect(filterPlugins(plugins, "repositories").map((plugin) => plugin.id)).toEqual(["repository"]);
    expect(filterPlugins(plugins, "web").map((plugin) => plugin.id)).toEqual(["web-search"]);
  });

  it("overrides persisted toggle state by plugin id", () => {
    const state = setPluginEnabled({}, "web-search", true);

    expect(pluginItems(state).find((plugin) => plugin.id === "web-search")?.isEnabled).toBe(true);
  });
});
