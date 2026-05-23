import { argon2id } from "hash-wasm";

export interface Argon2Params {
  passphrase: string;
  salt: Uint8Array;
  keyLen: number;
  opsLimit: number;
  memLimitBytes: number;
}

export async function deriveArgon2id(params: Argon2Params): Promise<Uint8Array> {
  const result = await argon2id({
    password: params.passphrase,
    salt: params.salt,
    parallelism: 1,
    iterations: params.opsLimit,
    memorySize: Math.floor(params.memLimitBytes / 1024),
    hashLength: params.keyLen,
    outputType: "binary"
  });
  return result instanceof Uint8Array ? result : new Uint8Array(result);
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error("hex string must contain full bytes");
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}
