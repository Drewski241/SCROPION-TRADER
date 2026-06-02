import type { PokerVariant } from "./types.js";

export interface VariantMeta {
  id: PokerVariant;
  label: string;
  holeCards: number;
  communityCards: number;
  bettingStructure: "no-limit" | "pot-limit" | "fixed-limit";
  chiaGamingNative: boolean;
  notes?: string;
}

/** Catalog of supported / planned variants for lobby and routing. */
export const POKER_VARIANTS: VariantMeta[] = [
  {
    id: "nlhe",
    label: "No-Limit Hold'em",
    holeCards: 2,
    communityCards: 5,
    bettingStructure: "no-limit",
    chiaGamingNative: false,
  },
  {
    id: "plhe",
    label: "Pot-Limit Hold'em",
    holeCards: 2,
    communityCards: 5,
    bettingStructure: "pot-limit",
    chiaGamingNative: false,
  },
  {
    id: "plo4",
    label: "Pot-Limit Omaha (4)",
    holeCards: 4,
    communityCards: 5,
    bettingStructure: "pot-limit",
    chiaGamingNative: false,
  },
  {
    id: "plo5",
    label: "Pot-Limit Omaha (5)",
    holeCards: 5,
    communityCards: 5,
    bettingStructure: "pot-limit",
    chiaGamingNative: false,
  },
  {
    id: "plo6",
    label: "Pot-Limit Omaha (6)",
    holeCards: 6,
    communityCards: 5,
    bettingStructure: "pot-limit",
    chiaGamingNative: false,
  },
  {
    id: "calpoker",
    label: "California Poker (Chia Gaming)",
    holeCards: 2,
    communityCards: 5,
    bettingStructure: "no-limit",
    chiaGamingNative: true,
    notes: "Reference implementation in chia-gaming; head-to-head state channels.",
  },
  {
    id: "stud",
    label: "Seven Card Stud",
    holeCards: 7,
    communityCards: 0,
    bettingStructure: "fixed-limit",
    chiaGamingNative: false,
  },
  {
    id: "razz",
    label: "Razz",
    holeCards: 7,
    communityCards: 0,
    bettingStructure: "fixed-limit",
    chiaGamingNative: false,
  },
  {
    id: "horse",
    label: "H.O.R.S.E.",
    holeCards: 2,
    communityCards: 5,
    bettingStructure: "fixed-limit",
    chiaGamingNative: false,
    notes: "Mixed rotation; engine delegates per street round.",
  },
];

export function getVariantMeta(id: PokerVariant): VariantMeta | undefined {
  return POKER_VARIANTS.find((v) => v.id === id);
}
