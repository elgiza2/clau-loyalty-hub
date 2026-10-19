/** Prize campaign constants shared by the popup, the wallet and the balances. */

/** Prize value announced to every player. */
export const PRIZE_USD = 25000;

/** Live market fallback for Gram (USD). Used when the market feed is unavailable. */
export const GRAM_USD_FALLBACK = 1.36;

/** Convert a USD amount into Gram at the given market price. */
export const usdToGram = (usd: number, gramPrice: number) =>
  gramPrice > 0 ? usd / gramPrice : 0;

/** Prize expressed in Gram at the given market price. */
export const prizeInGram = (gramPrice: number) => usdToGram(PRIZE_USD, gramPrice);
