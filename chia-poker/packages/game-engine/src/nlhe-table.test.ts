import { describe, expect, it } from "vitest";
import type { TableConfig } from "@chia-poker/shared";
import { NlheTableEngine } from "./nlhe-table.js";
import { generateServerSeed } from "./shuffle.js";

const config: TableConfig = {
  id: "table-1",
  variant: "nlhe",
  format: "cash",
  maxSeats: 6,
  smallBlindMojos: 50_000_000_000n,
  bigBlindMojos: 100_000_000_000n,
  minBuyInMojos: 2_000_000_000_000n,
  maxBuyInMojos: 20_000_000_000_000n,
  rakeBps: 500,
};

describe("NlheTableEngine", () => {
  it("runs commit-reveal deal and heads-up fold", () => {
    const table = new NlheTableEngine(config);
    table.seatPlayer("alice", 0, 5_000_000_000_000n);
    table.seatPlayer("bob", 1, 5_000_000_000_000n);

    const { commitHash } = table.startHand("hand-1");
    expect(commitHash).toHaveLength(64);

    table.submitPlayerSeed("alice", generateServerSeed());
    table.submitPlayerSeed("bob", generateServerSeed());
    table.revealAndDeal();

    const state = table.getHandState();
    expect(state?.players.every((p) => p.holeCards.length === 2)).toBe(true);

    table.applyAction("alice", "fold");
    expect(table.getHandState()).toBeNull();
  });
});
