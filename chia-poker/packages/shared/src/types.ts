export type PlayerId = string;
export type TableId = string;
export type HandId = string;
export type SessionId = string;

export type PokerVariant =
  | "nlhe"
  | "plhe"
  | "plo4"
  | "plo5"
  | "plo6"
  | "stud"
  | "razz"
  | "horse"
  | "calpoker";

export type TableFormat = "cash" | "sng" | "mtt";

export type CurrencyUnit = "xch" | "cat";

export interface Money {
  amountMojos: bigint;
  unit: CurrencyUnit;
}

export interface PlayerProfile {
  id: PlayerId;
  displayName: string;
  region?: string;
}

export interface TableConfig {
  id: TableId;
  variant: PokerVariant;
  format: TableFormat;
  maxSeats: number;
  smallBlindMojos: bigint;
  bigBlindMojos: bigint;
  minBuyInMojos: bigint;
  maxBuyInMojos: bigint;
  rakeBps: number;
}

export interface SeatState {
  seatIndex: number;
  playerId: PlayerId | null;
  stackMojos: bigint;
  sittingOut: boolean;
}

export type Street = "preflop" | "flop" | "turn" | "river" | "showdown";

export interface HandCommitment {
  handId: HandId;
  tableId: TableId;
  commitHash: string;
  createdAt: string;
}

export interface HandReveal {
  handId: HandId;
  serverSeed: string;
  playerSeeds: Record<PlayerId, string>;
}

export interface SettlementProof {
  handId: HandId;
  tableId: TableId;
  stateRootHash: string;
  payouts: Array<{ playerId: PlayerId; deltaMojos: bigint }>;
  chiaTxId?: string;
}
