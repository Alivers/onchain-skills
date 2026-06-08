# Unchecked External Call / ERC20 Assumptions

The contract assumes an external call or token transfer behaves "normally" — reverts
on failure, returns a bool, or that balances only change through its own logic. Real
tokens and accounts break those assumptions.

## Heuristic (the smell)

- `addr.call(...)` / `addr.send(...)` whose return value is ignored (a failed call
  silently treated as success).
- `token.transfer(...)` used without checking the return bool, on tokens that
  **return false** instead of reverting (or **return nothing**, like USDT) — code
  expecting `bool` reverts, code ignoring it loses funds.
- Logic relying on `address(this).balance == expected` or `token.balanceOf(this)`
  being controlled solely by its own accounting (defeated by **force-fed** ETH via
  `selfdestruct`, or by direct token donations).
- Trusting return data length / a callee not to **return-bomb** (huge returndata to
  exhaust gas), or push-payments that let a reverting recipient brick a loop.

## Where to look

Payout loops, `transfer`/`transferFrom` without `SafeERC20`, strict balance
invariants (`require(balance == ...)`), reward distribution, refunds, and any
integration with arbitrary/known-quirky tokens (USDT, BNB, fee-on-transfer, rebasing).

## Exploit mechanics

- **Silent failure:** a transfer that returns false is ignored; the contract credits
  the user anyway → double-spend / drain.
- **Force-feed griefing:** `selfdestruct(victim)` pushes ETH so `balance` exceeds the
  internal counter, breaking a `require(balance == internalTotal)` invariant and
  freezing or misrouting funds.
- **Fee-on-transfer mismatch:** contract credits the full `amount` but receives less
  (token takes a fee), so accounting > actual holdings → last withdrawers can't exit.
- **Push-payment DoS:** one recipient's `receive()` reverts, bricking a distribution
  loop for everyone.

## Minimal PoC sketch

```solidity
function test_feeOnTransferMismatch() public {
    // pool credits `amount`, but FOT token delivers amount*(1-fee)
    pool.deposit(1000e18);                 // internal balance += 1000e18
    // real tokens received < 1000e18; pool is now under-collateralized
    assertLt(token.balanceOf(address(pool)), pool.internalBalanceOf(address(this)));
}
```

## Fixes (to recognize a safe target)

OZ `SafeERC20` (`safeTransfer`/`safeTransferFrom`), check low-level call returns,
measure `balanceBefore/After` for fee-on-transfer tokens, pull-over-push payments,
and never rely on exact `balance` equality for invariants.

## Real-world cases

USDT/BNB non-standard return drains, fee-on-transfer accounting mismatches,
force-feeding to break strict-balance contracts, and reverting-recipient DoS loops.
