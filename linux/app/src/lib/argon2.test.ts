import { describe, expect, it } from "vitest";
import { bytesToHex, deriveArgon2id, hexToBytes } from "./argon2";

describe("deriveArgon2id", () => {
  it("matches the vault Argon2id test vector", async () => {
    const key = await deriveArgon2id({
      passphrase: "test",
      salt: hexToBytes("000102030405060708090a0b0c0d0e0f"),
      keyLen: 32,
      opsLimit: 3,
      memLimitBytes: 64 * 1024 * 1024
    });

    expect(bytesToHex(key)).toBe("15191553b0c3d6b77081eb9800df65c9aac503f5112ed7360af28b8af0a81e23");
  });
});
