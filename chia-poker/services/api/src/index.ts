import Fastify from "fastify";
import cors from "@fastify/cors";
import { ChiaGamingClient } from "@chia-poker/chia-bridge";
import { POKER_VARIANTS } from "@chia-poker/shared";
import { registerTableRoutes } from "./routes/tables.js";
import { registerHealthRoutes } from "./routes/health.js";

const port = Number(process.env.API_PORT ?? 4000);
const host = process.env.API_HOST ?? "0.0.0.0";

const chiaClient = new ChiaGamingClient({
  network: (process.env.CHIA_NETWORK as "mainnet" | "testnet") ?? "mainnet",
  lobbyUrl: process.env.CHIA_GAMING_LOBBY_URL ?? "http://localhost:3001",
  gameUrl: process.env.CHIA_GAMING_GAME_URL ?? "http://localhost:3000",
  coinsetUrl: process.env.COINSET_URL ?? "https://coinset.org",
  walletConnect: process.env.WALLETCONNECT_PROJECT_ID
    ? {
        projectId: process.env.WALLETCONNECT_PROJECT_ID,
        chainId: process.env.CHIA_CHAIN_ID ?? "chia:mainnet",
      }
    : undefined,
});

async function main(): Promise<void> {
  const app = Fastify({ logger: true });
  await app.register(cors, { origin: true });

  registerHealthRoutes(app, chiaClient);
  registerTableRoutes(app);

  app.get("/v1/variants", async () => ({
    variants: POKER_VARIANTS,
  }));

  await app.listen({ port, host });
  app.log.info(`API listening on http://${host}:${port}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
