import type { FastifyInstance } from "fastify";
import { randomUUID } from "node:crypto";
import type { TableConfig } from "@chia-poker/shared";
import { NlheTableEngine } from "@chia-poker/game-engine";

const tables = new Map<string, NlheTableEngine>();

export function registerTableRoutes(app: FastifyInstance): void {
  app.post<{
    Body: {
      variant?: string;
      smallBlindMojos?: string;
      bigBlindMojos?: string;
      maxSeats?: number;
    };
  }>("/v1/tables", async (req) => {
    const id = randomUUID();
    const config: TableConfig = {
      id,
      variant: "nlhe",
      format: "cash",
      maxSeats: req.body.maxSeats ?? 6,
      smallBlindMojos: BigInt(req.body.smallBlindMojos ?? "50000000000"),
      bigBlindMojos: BigInt(req.body.bigBlindMojos ?? "100000000000"),
      minBuyInMojos: 2_000_000_000_000n,
      maxBuyInMojos: 20_000_000_000_000n,
      rakeBps: 500,
    };
    tables.set(id, new NlheTableEngine(config));
    return { tableId: id, config };
  });

  app.get<{ Params: { tableId: string } }>("/v1/tables/:tableId", async (req, reply) => {
    const table = tables.get(req.params.tableId);
    if (!table) {
      return reply.status(404).send({ error: "Table not found" });
    }
    return {
      tableId: req.params.tableId,
      players: table.getActivePlayerCount(),
      hand: table.getHandState(),
    };
  });

  app.post<{
    Params: { tableId: string };
    Body: { playerId: string; seatIndex: number; buyInMojos: string };
  }>("/v1/tables/:tableId/seat", async (req, reply) => {
    const table = tables.get(req.params.tableId);
    if (!table) {
      return reply.status(404).send({ error: "Table not found" });
    }
    try {
      table.seatPlayer(req.body.playerId, req.body.seatIndex, BigInt(req.body.buyInMojos));
      return { ok: true };
    } catch (e) {
      return reply.status(400).send({ error: (e as Error).message });
    }
  });
}
