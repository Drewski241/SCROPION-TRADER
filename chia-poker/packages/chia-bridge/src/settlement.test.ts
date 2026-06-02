import { describe, expect, it } from "vitest";
import { buildSettlementProof, computeStateRoot } from "./settlement.js";

describe("settlement", () => {
  it("produces stable state roots", () => {
    const input = {
      handId: "h1",
      tableId: "t1",
      payouts: [{ playerId: "alice", deltaMojos: 100n }],
      eventLog: [{ seq: 1 }],
    };
    expect(computeStateRoot(input)).toBe(computeStateRoot(input));
    const proof = buildSettlementProof(input);
    expect(proof.stateRootHash).toHaveLength(64);
  });
});
