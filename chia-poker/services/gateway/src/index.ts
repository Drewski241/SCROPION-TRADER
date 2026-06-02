import { createServer } from "node:http";
import { WebSocketServer } from "ws";
import { randomUUID } from "node:crypto";

const port = Number(process.env.GATEWAY_PORT ?? 4100);
const host = process.env.GATEWAY_HOST ?? "0.0.0.0";

interface ClientMessage {
  type: string;
  tableId?: string;
  payload?: unknown;
}

const server = createServer((_req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ service: "chia-poker-gateway", status: "ok" }));
});

const wss = new WebSocketServer({ server, path: "/ws" });

wss.on("connection", (socket) => {
  const connectionId = randomUUID();
  socket.send(JSON.stringify({ type: "connected", connectionId }));

  socket.on("message", (raw) => {
    let msg: ClientMessage;
    try {
      msg = JSON.parse(String(raw)) as ClientMessage;
    } catch {
      socket.send(JSON.stringify({ type: "error", message: "Invalid JSON" }));
      return;
    }

    if (msg.type === "ping") {
      socket.send(JSON.stringify({ type: "pong", at: new Date().toISOString() }));
      return;
    }

    if (msg.type === "subscribe" && msg.tableId) {
      socket.send(
        JSON.stringify({
          type: "subscribed",
          tableId: msg.tableId,
          note: "Realtime table fanout will attach to regional game shards in production.",
        }),
      );
      return;
    }

    socket.send(JSON.stringify({ type: "error", message: `Unknown message type: ${msg.type}` }));
  });
});

server.listen(port, host, () => {
  console.log(`Gateway listening on ws://${host}:${port}/ws`);
});
