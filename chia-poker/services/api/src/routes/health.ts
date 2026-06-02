import type { FastifyInstance } from "fastify";
import type { ChiaGamingClient } from "@chia-poker/chia-bridge";

export function registerHealthRoutes(app: FastifyInstance, chia: ChiaGamingClient): void {
  app.get("/health", async () => ({ status: "ok", service: "chia-poker-api" }));

  app.get("/health/chia-gaming", async () => {
    const lobbyOk = await chia.pingLobby();
    return {
      lobby: lobbyOk ? "up" : "down",
      lobbyUrl: chia.lobbyBaseUrl,
      gameUrl: chia.gameBaseUrl,
    };
  });
}
