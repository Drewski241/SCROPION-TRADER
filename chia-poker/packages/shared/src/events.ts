import type { HandId, PlayerId, Street, TableId } from "./types.js";

export type GameEventType =
  | "table.created"
  | "player.seated"
  | "hand.started"
  | "hand.commit"
  | "street.dealt"
  | "action.posted"
  | "pot.awarded"
  | "hand.settled";

export interface BaseGameEvent {
  type: GameEventType;
  tableId: TableId;
  handId?: HandId;
  seq: number;
  at: string;
}

export interface ActionPostedEvent extends BaseGameEvent {
  type: "action.posted";
  handId: HandId;
  playerId: PlayerId;
  action: "fold" | "check" | "call" | "bet" | "raise" | "all-in";
  amountMojos: bigint;
  street: Street;
}

export type GameEvent = BaseGameEvent | ActionPostedEvent;
