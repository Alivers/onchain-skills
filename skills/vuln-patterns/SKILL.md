---
name: vuln-patterns
description: A library of historical EVM smart-contract vulnerability classes — each with a detection heuristic (the code smell that gives it away), the exploit mechanics, a minimal Foundry PoC sketch, and real-world examples. Use this whenever you need to reason about WHAT KIND of bug something is rather than a specific tx: naming the vuln class during a post-mortem, deciding what to check on a contract for a bug-bounty, asking "is this reentrancy / oracle manipulation / an access-control hole / a rounding bug", building an audit checklist, explaining how a class of attack works, or picking the right PoC template before writing one. It feeds the hypothesis step of tx-decoder and the template step of forge-poc. Triggers: "what vulnerability is this", "what should I check on this contract", "how does <attack class> work", "is this exploitable and how", "common DeFi vulns", "审计 checklist", "这是什么漏洞", "常见合约漏洞".
---

# vuln-patterns

A field guide to the vulnerability classes behind most EVM/DeFi exploits. Use it to
go from a symptom ("the attacker drained the vault in one tx with a flash loan") to
a named class, a detection heuristic, and a PoC shape you can hand to `forge-poc`.

This is knowledge, not a tx analyzer. Pair it with:
- **tx-decoder** — to read a specific attack tx; this library names what you're seeing.
- **forge-poc** — to actually reproduce it; each reference gives a PoC *sketch*, not a recipe.

## Read this first: lenses, not a checklist

These classes are **lenses for reasoning, not a catalog to match against.** The
references are deliberately simple, single-cause examples so the mechanic is clear —
but real exploits rarely look like one textbook entry:

- **They compose.** The big ones chain primitives: a flash loan funds an oracle skew
  that enables an under-collateralized borrow, where a rounding seam makes it
  profitable. Expect 2–4 classes stacked in one tx. Naming only the first one you
  recognize is how you miss the actual bug.
- **The library is not exhaustive.** Plenty of real bugs (governance/timelock abuse,
  MEV/sandwich-dependent logic, cross-chain message spoofing, callback ordering,
  liquidation edge cases, gas/DoS, novel protocol-specific invariants) aren't here.
  Absence from the table is **not** evidence of safety.
- **Reason from invariants, not keywords.** The durable question isn't "which class
  is this" but: *what invariant must always hold (solvency, share price monotonicity,
  1 share ≥ its assets, only-owner-can-X), what does the attacker fully control, and
  what's the cheapest way to make those two collide?* The class names are shorthand
  for recurring answers — use them to deepen a hypothesis, never to force a match or
  to stop looking once one fits.
- **The PoC sketches are illustrative shapes**, not drop-in code. Adapt the structure
  to the real target; don't transcribe constants.

So: use a reference to sharpen and pressure-test a hypothesis you already formed from
the actual code/trace — then prove it with `forge-poc`. If nothing in the table fits,
that's a signal to reason from first principles, not to conclude it's safe.

## How to use

- **Post-mortem (tx-decoder step 5):** the trace shows a primitive (a spot-price read,
  an external call before a state write, an unguarded mint…); open the matching
  reference to confirm mechanics and PoC shape — and ask what *else* in the same tx
  it's chained with.
- **Bug-bounty recon:** use *Where to look first* (below) as a reasoning order, not a
  tick-box list; for any candidate, open its reference to go deep.
- **Teaching:** each reference is self-contained (heuristic → mechanics → PoC → real
  cases). The fully-runnable reentrancy example lives at `test/examples/Reentrancy.t.sol`.

Only read the reference you need (progressive disclosure) — don't load all of them.

## The library

| Class | One-line heuristic (the smell) | Reference |
|---|---|---|
| Price / oracle manipulation | Protocol prices an asset from an AMM spot value (`getReserves`, pool `balanceOf`) it can move in the same tx | [references/price-oracle-manipulation.md](references/price-oracle-manipulation.md) |
| Reentrancy | External call (`.call`, token hook, callback) happens **before** state is updated; guard missing or mis-scoped | [references/reentrancy.md](references/reentrancy.md) |
| Access control | A state-changing privileged function lacks an auth check, or an initializer is callable by anyone / twice | [references/access-control.md](references/access-control.md) |
| Vault share inflation | First depositor mints 1 wei of shares then *donates* assets directly, so a victim's deposit rounds to 0 shares | [references/erc4626-inflation.md](references/erc4626-inflation.md) |
| Signature replay / forgery | `ecrecover`-based auth without nonce, domain separator, or deadline; sig reusable across tx/contract/chain | [references/signature-replay.md](references/signature-replay.md) |
| Delegatecall / proxy storage | `delegatecall` where caller/callee storage layouts differ, or an uninitialized implementation is reachable | [references/delegatecall-storage.md](references/delegatecall-storage.md) |
| Arithmetic / rounding | Division rounds in the user's favor, decimals mismatch (6 vs 18), `unchecked`, or a profitable mint→redeem round-trip | [references/arithmetic-rounding.md](references/arithmetic-rounding.md) |
| Unchecked external call | Low-level call / transfer return value ignored, non-standard ERC20 assumptions, or reliance on exact `balance` | [references/unchecked-call.md](references/unchecked-call.md) |

Flash loans aren't a class on their own — they're an **amplifier** that gives an
attacker temporary capital to trigger the classes above (most often oracle
manipulation and accounting/rounding) within a single atomic tx.

## Where to look first (recon ordering)

When you don't yet have a hypothesis, scan in this order — it's roughly the
frequency-weighted order of real losses:

1. **How are prices/amounts derived?** Any spot read from a pool → oracle manipulation.
2. **External calls** — any call to a user-controlled address or hook-bearing token
   before state settles → reentrancy.
3. **Privileged functions & initializers** — who can call mint/withdraw/upgrade/init.
4. **Accounting math** — share/asset conversions, fees, decimals, rounding direction.
5. **Proxy/upgrade paths** — delegatecall targets, storage layout, init guards.

## Extending the library

Each new class is a `references/<class>.md` with the same shape: **Heuristic →
Where to look → Exploit mechanics → Minimal PoC sketch → Real-world cases**. Add a
row to the table above. Promote a sketch to a runnable `test/examples/*.t.sol` when
it's worth keeping as a template.
