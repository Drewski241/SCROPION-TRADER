export type ChiaNetwork = "mainnet" | "testnet";

export interface StateChannelSession {
  sessionId: string;
  playerA: string;
  playerB: string;
  stakeMojos: bigint;
  lobbyRoomId?: string;
  status: "opening" | "active" | "closing" | "disputed" | "closed";
  openedAt?: string;
  closedAt?: string;
}

export interface LobbyRoom {
  roomId: string;
  inviteUrl: string;
  variant: string;
  createdAt: string;
}

export interface WalletConnectConfig {
  projectId: string;
  chainId: string;
}

export interface ChiaBridgeConfig {
  network: ChiaNetwork;
  lobbyUrl: string;
  gameUrl: string;
  coinsetUrl: string;
  walletConnect?: WalletConnectConfig;
}
