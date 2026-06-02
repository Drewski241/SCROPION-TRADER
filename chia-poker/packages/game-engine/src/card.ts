export type Suit = "c" | "d" | "h" | "s";
export type Rank = "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "T" | "J" | "Q" | "K" | "A";

export interface Card {
  rank: Rank;
  suit: Suit;
}

const RANK_ORDER: Record<Rank, number> = {
  "2": 2,
  "3": 3,
  "4": 4,
  "5": 5,
  "6": 6,
  "7": 7,
  "8": 8,
  "9": 9,
  T: 10,
  J: 11,
  Q: 12,
  K: 13,
  A: 14,
};

export function cardToString(card: Card): string {
  return `${card.rank}${card.suit}`;
}

export function parseCard(s: string): Card {
  if (s.length !== 2) {
    throw new Error(`Invalid card: ${s}`);
  }
  const rank = s[0] as Rank;
  const suit = s[1] as Suit;
  if (!(rank in RANK_ORDER) || !"cdhs".includes(suit)) {
    throw new Error(`Invalid card: ${s}`);
  }
  return { rank, suit };
}

export function rankValue(rank: Rank): number {
  return RANK_ORDER[rank];
}

export function standardDeck(): Card[] {
  const suits: Suit[] = ["c", "d", "h", "s"];
  const ranks: Rank[] = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"];
  const deck: Card[] = [];
  for (const suit of suits) {
    for (const rank of ranks) {
      deck.push({ rank, suit });
    }
  }
  return deck;
}
