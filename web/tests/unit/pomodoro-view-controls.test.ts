import { afterEach, describe, expect, it, vi } from "vitest";
import { PanelButton, download } from "../../src/screens/pomodoro/pomodoro-view-controls";

describe("pomodoro view controls", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("keeps panel button selection wiring stable", () => {
    let selected = "";
    const element = PanelButton({
      panel: "timer",
      current: "analytics",
      icon: "clock",
      label: "Timer",
      onClick: (panel) => {
        selected = panel;
      },
    }) as any;

    expect(element.type).toBe("button");
    expect(element.props.children[1].props.children).toBe("Timer");

    element.props.onClick();

    expect(selected).toBe("timer");
  });

  it("keeps download helper blob URL lifecycle stable", () => {
    const click = vi.fn();
    const link = { href: "", download: "", click };
    const createElement = vi.fn(() => link);
    const createObjectURL = vi.fn(() => "blob:pomodoro-export");
    const revokeObjectURL = vi.fn();

    vi.stubGlobal("document", { createElement });
    vi.stubGlobal("URL", { createObjectURL, revokeObjectURL });

    download("session-export.json", "{\"ok\":true}", "application/json");

    expect(createElement).toHaveBeenCalledWith("a");
    expect(createObjectURL).toHaveBeenCalledWith(expect.any(Blob));
    expect(link.href).toBe("blob:pomodoro-export");
    expect(link.download).toBe("session-export.json");
    expect(click).toHaveBeenCalledOnce();
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:pomodoro-export");
  });
});
