import type { SettlementProof } from "@chia-poker/shared";
import { createHash } from "node:crypto";

export interface SettlementInput {
  handId: string;
  tableId: string;
  payouts: Array<{ playerId: string; deltaMojos: bigint }>;
  eventLog: unknown[];
}

/** Build a deterministic state root for anchoring / audit. */
export function computeStateRoot(input: SettlementInput): string {
  const payload = JSON.stringify({
    handId: input.handId,
    tableId: input.tableId,
    payouts: input.payouts.map((p) => ({
      playerId: p.playerId,
      deltaMojos: p.deltaMojos.toString(),
    })),
    events: input.eventLog,
  });
  return createHash("sha256").update(payload).digest("hex");
}

export function buildSettlementProof(input: SettlementInput, chiaTxId?: string): SettlementProof {
  const stateRootHash = computeStateRoot(input);
  return {
    handId: input.handId,
    tableId: input.tableId,
    stateRootHash,
    payouts: input.payouts,
    chiaTxId,
  };
}
