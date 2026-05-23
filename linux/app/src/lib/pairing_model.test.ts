import { describe, expect, it } from "vitest";
import pairingPayload from "../../../../packages/ClawixCore/Fixtures/BridgeV1/027-pairingPayload.json";
import { pairingDetails } from "./pairing_model";

describe("pairingDetails", () => {
  it("extracts manual pairing details from the BridgeV1 pairing payload fixture", () => {
    const details = pairingDetails(pairingPayload);

    expect(details.shortCode).toBe("ABC-234-XYZ");
    expect(details.host).toBe("127.0.0.1");
    expect(details.port).toBe(24080);
    expect(details.hostDisplayName).toBe("Fixture Mac");
    expect(details.manualAddress).toBe("127.0.0.1:24080");
    expect(details.isLoopback).toBe(true);
  });

  it("keeps the short code usable when qrJson is malformed", () => {
    const details = pairingDetails({
      shortCode: "LIN-123-PAIR",
      token: "token-linux",
      qrJson: "{"
    });

    expect(details.shortCode).toBe("LIN-123-PAIR");
    expect(details.token).toBe("token-linux");
    expect(details.host).toBeNull();
    expect(details.port).toBeNull();
    expect(details.manualAddress).toBeNull();
  });
});
