---
name: invariant-testing
description: Discover bugs you don't yet have a hypothesis for by writing Foundry invariant and fuzz tests — define the properties that must always hold (solvency, share-price monotonicity, accounting identities, access control) and let the fuzzer search for a sequence that breaks them. Use this for proactive bug-finding rather than proving a known bug: bug-bounty/audit exploration, "find a vulnerability in this contract", "what could break here", "fuzz this protocol", "write invariant tests", stress-testing accounting or AMM math, or hunting an exploit when you only have a hunch. It sits between vuln-patterns (which suggests which invariants to test) and forge-poc (which hardens a broken invariant into a clean exploit PoC). Triggers: "find bugs", "fuzz this", "invariant test", "what can break", "stress test the accounting", "属性测试", "模糊测试", "主动找漏洞". For proving a SPECIFIC bug you already understand, use forge-poc instead.
---

# invariant-testing

`forge-poc` proves a bug you already found. This skill **finds** it: you state what
must always be true, and Foundry's fuzzer hunts for a call sequence that violates it.
The art is choosing invariants sharp enough to catch real bugs and a handler realistic
enough to reach them.

## Stateless fuzz vs stateful invariant

- **Fuzz test** (`testFuzz_*(uint256 x)`): one function, random inputs, checked each run.
  Good for pure math / a single entrypoint (rounding, decimals, over/underflow seams).
- **Invariant test** (`invariant_*()`): the fuzzer calls **random sequences** of your
  target functions, then asserts the invariant after each step. This is where protocol
  bugs live — they emerge from *interactions across calls*, not one call.

## Workflow

1. **State the invariants** — the properties that must hold no matter what. Derive them
   from the protocol's promises and from `vuln-patterns` (each class is a violated
   invariant). Strong, general invariants:
   - **Solvency / backing:** `totalAssets() >= totalSupply()` priced correctly; sum of
     user balances == `totalSupply`; vault holds ≥ what it owes.
   - **Share price monotonic:** price-per-share never drops except on real loss; a
     deposit-then-withdraw round-trip returns **≤** what went in (no free money).
   - **Conservation:** tokens in == tokens out + fees; no address gains value from a
     no-op sequence.
   - **Access:** privileged state (owner, oracle, paused) only changes via authorized
     callers.
2. **Write a handler** — a contract of *bounded* actions the fuzzer drives, so it
   explores realistic states instead of reverting constantly. Clamp inputs with
   `bound()`, manage a set of actors, and track **ghost variables** (e.g. sum of all
   deposits) to express invariants the contract doesn't expose directly.
3. **Wire targets** in `setUp()`: `targetContract(address(handler))`,
   `targetSelector(...)`, `targetSender(...)`, `excludeContract(...)` to focus the search.
4. **Run** `forge test --match-contract Invariant -vvv`. Tune `[invariant]` in foundry.toml.
5. **On a break:** the fuzzer prints the failing **call sequence**. Shrink/minimize it,
   understand the mechanism (name it via `vuln-patterns`), then hand it to **forge-poc**
   to turn into a clean, asserted exploit.

## Handler skeleton

```solidity
contract Handler is Test {
    Vault vault; Token token;
    address[] actors; address current;
    uint256 public ghostDeposited;   // ghost var: invariant references this

    modifier useActor(uint256 s) { current = actors[bound(s,0,actors.length-1)]; vm.startPrank(current); _; vm.stopPrank(); }

    function deposit(uint256 assets, uint256 a) external useActor(a) {
        assets = bound(assets, 0, token.balanceOf(current));
        token.approve(address(vault), assets);
        vault.deposit(assets, current);
        ghostDeposited += assets;           // track for the solvency invariant
    }
    function withdraw(uint256 shares, uint256 a) external useActor(a) {
        shares = bound(shares, 0, vault.balanceOf(current));
        ghostDeposited -= vault.redeem(shares, current, current);
    }
}

contract VaultInvariant is StdInvariant, Test {
    Handler handler;
    function setUp() public { /* deploy */ handler = new Handler(...); targetContract(address(handler)); }

    function invariant_solvency() public view {
        assertGe(token.balanceOf(address(vault)), ghostOwed(), "vault undercollateralized");
    }
}
```

## Config (foundry.toml)

```toml
[invariant]
runs = 256          # independent sequences
depth = 64          # calls per sequence
fail_on_revert = false   # true once your handler is clean = stronger signal
[fuzz]
runs = 1000
```
- Start `fail_on_revert = false` (so reverts don't end runs while the handler is rough),
  then flip to `true` once handlers bound inputs properly — a clean handler that never
  reverts explores far deeper.

## Fork-mode invariants

Run invariants against **real deployed state** by forking (see `forge-poc` / `chain-access`):
target the live protocol contracts, seed actors with `deal`, and let the fuzzer attack
production logic. Great for bounties on deployed code where reproducing local deploy is hard.

## Where it fits

- **vuln-patterns** → tells you *which* invariants are worth asserting for this protocol type.
- **invariant-testing** (here) → searches for a violating sequence.
- **forge-poc** → hardens the discovered sequence into a deterministic, profit-asserting PoC.

## Honesty

A passing invariant suite is **evidence, not proof** — it only shows the fuzzer didn't
find a break within the configured runs/depth, and only for invariants you thought to
write. Report coverage honestly (which properties, how many runs, fork or local); absence
of a failure is not a security guarantee.
