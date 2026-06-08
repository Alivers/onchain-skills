# Arithmetic / Rounding

Not Solidity-0.8 overflow (that reverts now) but the subtler family: rounding that
favors the attacker, decimals mismatches, precision loss, and `unchecked` mistakes.

## Heuristic (the smell)

- Division **before** multiplication (`a / b * c`) — truncates precision; sometimes
  the attacker keeps the dust, sometimes it zeroes a victim's amount.
- Rounding direction favors the user on **both** mint and redeem, so a round-trip
  (`deposit` → `withdraw`, or `mint` → `burn`) returns more than it cost.
- **Decimals mismatch:** mixing a 6-decimal token (USDC/USDT) with an 18-decimal one
  without scaling, or assuming `decimals() == 18`.
- `unchecked { }` blocks where an input can still underflow/overflow, or downcasts
  (`uint256 -> uint128`) that truncate.
- Fee/interest math that rounds the protocol's favor to zero, or share math where
  `mulDiv` rounding can be steered.

## Where to look

Vault share/asset conversions, AMM/curve math, fee and interest accrual,
liquidation bonus math, anywhere two tokens of different decimals interact, and any
`unchecked`/cast.

## Exploit mechanics

- **Round-trip profit:** find the rounding seam and repeat a tiny mint→redeem many
  times, skimming dust each loop until it's material (cheap on L2s).
- **Zeroing a victim:** size a donation/state so the victim's `amount * X / Y` rounds
  to 0 (see also `erc4626-inflation.md`).
- **Decimals confusion:** deposit a 6-decimal token credited as if 18-decimal (or
  vice versa) to mint vastly more/less than intended.

## Minimal PoC sketch

```solidity
function test_roundTripProfit() public {
    uint256 start = token.balanceOf(address(this));
    for (uint256 i; i < 1000; ++i) {
        uint256 shares = vault.deposit(SMALL);    // rounds up in our favor
        vault.redeem(shares);                      // rounds up again
    }
    assertGt(token.balanceOf(address(this)), start, "free money from rounding");
}
```

## Fixes (to recognize a safe target)

`mulDiv` with explicit rounding direction (always against the user), multiply before
divide, scale by `10**decimals()` read at runtime, avoid unnecessary `unchecked`,
and SafeCast for downcasts.

## Real-world cases

Many vault/lending rounding drains and "1 wei" precision bugs; decimals-mismatch
mispricings; compounding dust attacks on low-fee chains.
