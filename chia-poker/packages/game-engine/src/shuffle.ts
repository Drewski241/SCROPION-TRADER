import { createHash, randomBytes } from "node:crypto";
import type { Card } from "./card.js";

export interface CommitRevealMaterial {
  serverSeed: string;
  commitHash: string;
}

export function generateServerSeed(): string {
  return randomBytes(32).toString("hex");
}

export function hashSeed(seed: string): string {
  return createHash("sha256").update(seed, "utf8").digest("hex");
}

export function createCommit(serverSeed: string): CommitRevealMaterial {
  return {
    serverSeed,
    commitHash: hashSeed(serverSeed),
  };
}

export function verifyCommit(serverSeed: string, commitHash: string): boolean {
  return hashSeed(serverSeed) === commitHash;
}

/** Deterministic Fisher-Yates shuffle from combined entropy. */
export function shuffleDeck(deck: Card[], entropy: string): Card[] {
  const out = [...deck];
  let state = createHash("sha256").update(entropy).digest();

  for (let i = out.length - 1; i > 0; i--) {
    const slice = state.subarray(0, 4);
    const rand = slice.readUInt32BE(0);
    const j = rand % (i + 1);
    [out[i], out[j]] = [out[j], out[i]];
    state = createHash("sha256").update(state).update(String(i)).digest();
  }

  return out;
}

export function buildShuffleEntropy(
  serverSeed: string,
  playerSeeds: Record<string, string>,
): string {
  const parts = [serverSeed, ...Object.keys(playerSeeds).sort().map((k) => `${k}:${playerSeeds[k]}`)];
  return parts.join("|");
}
