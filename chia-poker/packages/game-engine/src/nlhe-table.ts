import type { HandId, PlayerId, Street, TableConfig } from "@chia-poker/shared";
import { standardDeck, type Card } from "./card.js";
import { compareHands, evaluateBestHand } from "./hand-evaluator.js";
import {
  buildShuffleEntropy,
  createCommit,
  generateServerSeed,
  shuffleDeck,
  verifyCommit,
} from "./shuffle.js";

export type PlayerAction = "fold" | "check" | "call" | "bet" | "raise" | "all-in";

export interface PlayerHandState {
  playerId: PlayerId;
  seatIndex: number;
  holeCards: Card[];
  stackMojos: bigint;
  betThisStreetMojos: bigint;
  totalBetHandMojos: bigint;
  folded: boolean;
  allIn: boolean;
}

export interface TableHandState {
  handId: HandId;
  tableId: string;
  street: Street;
  board: Card[];
  potMojos: bigint;
  currentBetMojos: bigint;
  dealerSeat: number;
  actionSeat: number | null;
  players: PlayerHandState[];
  commitHash: string;
  serverSeed: string | null;
  playerSeeds: Record<PlayerId, string>;
  deck: Card[];
  deckIndex: number;
  seq: number;
}

export class NlheTableEngine {
  private config: TableConfig;
  private seats: Map<number, PlayerId> = new Map();
  private stacks: Map<PlayerId, bigint> = new Map();
  private hand: TableHandState | null = null;

  constructor(config: TableConfig) {
    this.config = config;
  }

  seatPlayer(playerId: PlayerId, seatIndex: number, buyInMojos: bigint): void {
    if (seatIndex < 0 || seatIndex >= this.config.maxSeats) {
      throw new Error("Invalid seat");
    }
    if (this.seats.has(seatIndex)) {
      throw new Error("Seat taken");
    }
    if (buyInMojos < this.config.minBuyInMojos || buyInMojos > this.config.maxBuyInMojos) {
      throw new Error("Buy-in out of range");
    }
    this.seats.set(seatIndex, playerId);
    this.stacks.set(playerId, buyInMojos);
  }

  getActivePlayerCount(): number {
    return this.seats.size;
  }

  startHand(handId: HandId): { commitHash: string } {
    if (this.seats.size < 2) {
      throw new Error("Need at least 2 players");
    }
    if (this.hand) {
      throw new Error("Hand already in progress");
    }

    const serverSeed = generateServerSeed();
    const { commitHash } = createCommit(serverSeed);
    const seated = [...this.seats.entries()].sort((a, b) => a[0] - b[0]);

    const players: PlayerHandState[] = seated.map(([seatIndex, playerId]) => ({
      playerId,
      seatIndex,
      holeCards: [],
      stackMojos: this.stacks.get(playerId) ?? 0n,
      betThisStreetMojos: 0n,
      totalBetHandMojos: 0n,
      folded: false,
      allIn: false,
    }));

    this.hand = {
      handId,
      tableId: this.config.id,
      street: "preflop",
      board: [],
      potMojos: 0n,
      currentBetMojos: 0n,
      dealerSeat: seated[0][0],
      actionSeat: seated[0][0],
      players,
      commitHash,
      serverSeed,
      playerSeeds: {},
      deck: standardDeck(),
      deckIndex: 0,
      seq: 0,
    };

    return { commitHash };
  }

  submitPlayerSeed(playerId: PlayerId, seed: string): void {
    const h = this.requireHand();
    if (!h.players.some((p) => p.playerId === playerId)) {
      throw new Error("Player not in hand");
    }
    h.playerSeeds[playerId] = seed;
  }

  revealAndDeal(): void {
    const h = this.requireHand();
    if (!h.serverSeed) {
      throw new Error("No server seed");
    }
    if (!verifyCommit(h.serverSeed, h.commitHash)) {
      throw new Error("Commit mismatch");
    }

    const activeIds = h.players.map((p) => p.playerId);
    const missing = activeIds.filter((id) => !h.playerSeeds[id]);
    if (missing.length > 0) {
      throw new Error(`Missing player seeds: ${missing.join(",")}`);
    }

    const entropy = buildShuffleEntropy(h.serverSeed, h.playerSeeds);
    h.deck = shuffleDeck(h.deck, entropy);

    for (const p of h.players) {
      p.holeCards = [this.draw(h), this.draw(h)];
    }

    this.postBlinds(h);
    h.seq++;
  }

  applyAction(playerId: PlayerId, action: PlayerAction, amountMojos: bigint = 0n): void {
    const h = this.requireHand();
    const player = this.getPlayer(h, playerId);
    if (player.folded || player.allIn) {
      throw new Error("Player cannot act");
    }

    switch (action) {
      case "fold":
        player.folded = true;
        break;
      case "check":
        if (player.betThisStreetMojos < h.currentBetMojos) {
          throw new Error("Cannot check facing a bet");
        }
        break;
      case "call": {
        const toCall = h.currentBetMojos - player.betThisStreetMojos;
        this.charge(player, h, toCall);
        break;
      }
      case "bet":
      case "raise": {
        if (amountMojos <= h.currentBetMojos) {
          throw new Error("Raise must exceed current bet");
        }
        const add = amountMojos - player.betThisStreetMojos;
        this.charge(player, h, add);
        h.currentBetMojos = player.betThisStreetMojos;
        break;
      }
      case "all-in": {
        const add = player.stackMojos;
        this.charge(player, h, add);
        player.allIn = true;
        if (player.betThisStreetMojos > h.currentBetMojos) {
          h.currentBetMojos = player.betThisStreetMojos;
        }
        break;
      }
      default:
        throw new Error(`Unknown action: ${action}`);
    }

    h.seq++;

    if (this.activePlayers(h).length <= 1) {
      this.awardToWinner(h);
      return;
    }

    if (this.bettingRoundComplete(h)) {
      this.advanceStreet(h);
    }
  }

  getHandState(): TableHandState | null {
    return this.hand ? structuredClone(this.hand) : null;
  }

  private requireHand(): TableHandState {
    if (!this.hand) throw new Error("No active hand");
    return this.hand;
  }

  private draw(h: TableHandState): Card {
    const card = h.deck[h.deckIndex];
    if (!card) throw new Error("Deck exhausted");
    h.deckIndex++;
    return card;
  }

  private postBlinds(h: TableHandState): void {
    const ordered = [...h.players].sort((a, b) => a.seatIndex - b.seatIndex);
    const sb = ordered[0];
    const bb = ordered[1] ?? ordered[0];

    this.charge(sb, h, this.config.smallBlindMojos);
    this.charge(bb, h, this.config.bigBlindMojos);
    h.currentBetMojos = bb.betThisStreetMojos;
    h.actionSeat = ordered[2]?.seatIndex ?? ordered[0].seatIndex;
  }

  private charge(player: PlayerHandState, h: TableHandState, amount: bigint): void {
    const pay = amount > player.stackMojos ? player.stackMojos : amount;
    player.stackMojos -= pay;
    player.betThisStreetMojos += pay;
    player.totalBetHandMojos += pay;
    h.potMojos += pay;
    this.stacks.set(player.playerId, player.stackMojos);
  }

  private getPlayer(h: TableHandState, playerId: PlayerId): PlayerHandState {
    const p = h.players.find((x) => x.playerId === playerId);
    if (!p) throw new Error("Player not in hand");
    return p;
  }

  private activePlayers(h: TableHandState): PlayerHandState[] {
    return h.players.filter((p) => !p.folded);
  }

  private bettingRoundComplete(h: TableHandState): boolean {
    const contenders = h.players.filter((p) => !p.folded && !p.allIn);
    if (contenders.length === 0) return true;
    return contenders.every((p) => p.betThisStreetMojos === h.currentBetMojos);
  }

  private advanceStreet(h: TableHandState): void {
    for (const p of h.players) {
      p.betThisStreetMojos = 0n;
    }
    h.currentBetMojos = 0n;

    const next: Record<Street, Street | "showdown"> = {
      preflop: "flop",
      flop: "turn",
      turn: "river",
      river: "showdown",
      showdown: "showdown",
    };

    const street = next[h.street];
    if (street === "showdown") {
      this.runShowdown(h);
      return;
    }

    h.street = street;
    const count = street === "flop" ? 3 : 1;
    for (let i = 0; i < count; i++) {
      h.board.push(this.draw(h));
    }
    h.actionSeat = h.dealerSeat;
    h.seq++;
  }

  private runShowdown(h: TableHandState): void {
    h.street = "showdown";
    const live = this.activePlayers(h);
    let best = live[0];
    let bestEval = evaluateBestHand([...best.holeCards, ...h.board]);

    for (const p of live.slice(1)) {
      const ev = evaluateBestHand([...p.holeCards, ...h.board]);
      if (compareHands(ev, bestEval) > 0) {
        best = p;
        bestEval = ev;
      }
    }

    best.stackMojos += h.potMojos;
    this.stacks.set(best.playerId, best.stackMojos);
    h.potMojos = 0n;
    this.hand = null;
  }

  private awardToWinner(h: TableHandState): void {
    const winner = this.activePlayers(h)[0];
    winner.stackMojos += h.potMojos;
    this.stacks.set(winner.playerId, winner.stackMojos);
    h.potMojos = 0n;
    this.hand = null;
  }
}
