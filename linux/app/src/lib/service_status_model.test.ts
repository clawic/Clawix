import { describe, expect, it } from "vitest";
import { serviceStatusRows } from "./service_status_model";

describe("serviceStatusRows", () => {
  it("formats running services with an ok tone", () => {
    expect(serviceStatusRows([{ id: "bridge", state: "running", port: 24080, pid: 123, restartCount: 1 }])).toEqual([
      { id: "bridge", detail: "running · :24080 · pid 123 · 1 restarts", tone: "ok" }
    ]);
  });

  it("marks services with errors as warnings", () => {
    expect(serviceStatusRows([{ id: "worker", state: "stopped", lastError: "crashed" }])).toEqual([
      { id: "worker", detail: "stopped · no port · no pid · restarts unknown · crashed", tone: "warn" }
    ]);
  });
});
