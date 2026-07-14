import { createHash, createHmac, createPrivateKey, createPublicKey } from "node:crypto";

const ED25519_PKCS8_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");
const HKDF_INFO = "wqc-operator-v1";

function hkdfExpand(prk, info, length) {
  const chunks = [];
  let t = Buffer.alloc(0);
  let counter = 1;
  while (Buffer.concat(chunks).length < length) {
    const mac = createHmac("sha256", prk);
    mac.update(t);
    mac.update(info);
    mac.update(Buffer.from([counter]));
    t = mac.digest();
    chunks.push(t);
    counter += 1;
  }
  return Buffer.concat(chunks).subarray(0, length);
}

function hkdfSha256(ikm, info, length) {
  const salt = Buffer.alloc(32, 0);
  const prk = createHmac("sha256", salt).update(ikm).digest();
  return hkdfExpand(prk, Buffer.from(info, "utf8"), length);
}

/** Mirrors wqc-node/src/domain/operator.rs and testnet.world-qc.io operator derivation. */
export function deriveOperatorFromNodeKey(nodeKey) {
  const seed = hkdfSha256(nodeKey, HKDF_INFO, 32);
  const privateKey = createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, seed]),
    format: "der",
    type: "pkcs8",
  });
  const publicKey = createPublicKey(privateKey);
  const spki = publicKey.export({ type: "spki", format: "der" });
  const pubBytes = spki.subarray(spki.length - 32);
  const operatorId = createHash("sha256").update(pubBytes).digest("hex");
  return {
    operatorId,
    publicKeyB64: pubBytes.toString("base64"),
  };
}
