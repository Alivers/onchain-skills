---
name: forge-poc
description: Write and run a Foundry fork-based proof-of-concept that proves an EVM contract vulnerability by reproducing it as a passing `forge test`. Use this whenever the user wants to fork mainnet or an L2 at a specific block, reproduce a past hack, demonstrate that a bug is actually exploitable, manipulate on-chain state in a test (impersonate accounts with prank, set balances/storage with deal/store), measure an attacker's profit, or turn an attack hypothesis into runnable code — even if they don't say "PoC" explicitly. This is the write-and-execute counterpart to tx-decoder (which only reads/explains an existing tx): reach for forge-poc the moment the goal shifts from understanding to proving. Triggers: "write a PoC", "fork at block X", "reproduce this exploit/hack", "is this actually exploitable", "prove the bug", "复现攻击", "写个 PoC", "这个漏洞能打通吗".
---

# forge-poc

Turn an attack hypothesis into a runnable, pinned-block Foundry PoC. The PoC is
the verification loop for every other analysis: if it runs green, the claim is real.

## Bootstrap (if the current project isn't a Foundry workspace yet)

This skill needs a Foundry project on disk (`foundry.toml`, `forge-std`, the
`PoCTest` base). The repo this skill ships from has it; an arbitrary project may not.

If `foundry.toml` is **missing** in the working directory, scaffold it from the
plugin root (the cloned skills repo), then install deps:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-.}"   # set when run as an installed plugin
cp "$ROOT/foundry.toml" .
mkdir -p test/base && cp "$ROOT/test/base/PoCTest.sol" test/base/
cp -n "$ROOT/.env.example" .env.example 2>/dev/null || true
forge install foundry-rs/forge-std
```

If `foundry.toml` already exists, skip this.

## Prerequisites (check first)

1. `.env` exists with an **archive** RPC for the target chain. Forking historical
   blocks needs archive nodes — public RPCs fail with `missing trie node`.
   If `.env` is missing, copy `.env.example` and tell the user which key to fill.
2. Confirm fork access before writing much: `cast block <N> --rpc-url <alias>`.
3. `foundry.toml` defines rpc aliases (mainnet, arbitrum, base, bsc, …) and
   Etherscan V2. Add new chains there, not inline.

## The workflow

1. **Pin the block.** For a post-mortem, fork at `attack_block - 1` to get the
   exact pre-attack state. For a bug-bounty PoC, fork at a recent finalized block.
   Never fork "latest" in a committed PoC — it's non-deterministic.
2. **Declare only the interface you touch.** Don't fetch full source unless you
   need it. Write a minimal `interface ITarget { ... }` for the functions you call.
   (Pull real ABIs with the `contract-recon` skill when the surface is unclear.)
3. **Extend `PoCTest`** (`test/base/PoCTest.sol`) and fork in `setUp()`.
4. **Write the attack** in `test_*`. Assert the profit/invariant break at the end
   so green == exploited.
5. **Run with traces:** `forge test --match-contract <Name> -vvvv`. Read the trace
   top-down — it's the same call tree a tx decoder shows, but you control inputs.

## Skeleton

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoCTest, console} from "../base/PoCTest.sol";

interface ITarget {
    function vulnerableFn(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
}

contract MyExploit is PoCTest {
    ITarget constant TARGET = ITarget(0x0000000000000000000000000000000000000000);
    address constant TOKEN  = 0x0000000000000000000000000000000000000000;

    function setUp() public {
        _fork("mainnet", 19_000_000); // attack_block - 1
    }

    function test_exploit() public {
        _logBalance("attacker before:", TOKEN, address(this));
        // ... attack steps ...
        _logBalance("attacker after: ", TOKEN, address(this));
        assertGt(/* profit */ 0, 0, "no profit -> not exploitable");
    }
}
```

## Cheatcodes you'll reach for

| Goal | Cheatcode |
|---|---|
| Become any address | `vm.prank(addr)` / `vm.startPrank(addr)` … `vm.stopPrank()` |
| Give ETH | `vm.deal(addr, 100 ether)` |
| Give ERC20 (mint-free) | `deal(token, addr, amount)` (forge-std StdCheats) |
| Overwrite a storage slot | `vm.store(target, slot, value)` (find slot via `cast storage`) |
| Read a storage slot | `vm.load(target, slot)` |
| Move time / blocks | `vm.warp(ts)` / `vm.roll(block)` |
| Expect a revert | `vm.expectRevert(bytes)` |
| Label trace addresses | `vm.label(addr, "Vault")` |

## Patterns by use case

- **Post-mortem replay:** fork at `attack_block - 1`, re-run the attacker's steps
  from a fresh attacker EOA. Cross-check the resulting trace against the real tx
  (use `tx-decoder`). Matching profit == faithful reproduction.
- **Bug-bounty PoC:** fork recent block, fund a clean attacker, demonstrate value
  extraction or a broken invariant. Keep it minimal — reviewers re-run it.
- **Teaching:** prefer self-contained PoCs (no fork) like `test/examples/Reentrancy.t.sol`
  so they run anywhere; add a `## VULN CLASS` comment explaining the heuristic.

## Common failure modes

- `missing trie node` / `header not found` → RPC isn't archive, or block too old
  for that provider. Use a real archive endpoint.
- Fork is slow / rate-limited → pin the block (caches state) and avoid re-forking
  every test; one `setUp` fork is reused across `test_*` in the contract.
- State looks wrong → you forked the attack block instead of `attack_block - 1`.
- `deal` on rebasing/proxy tokens may not work → set the storage slot directly
  with `vm.store` (locate it via `cast storage <token> <slot>` or `forge inspect`).

## Verify before claiming success

Run the test and read the assertion + trace. Only report "exploitable" / "reproduced"
when the test passes AND the profit/invariant assertion is the thing being asserted —
not a tautology. Report the command and the result honestly; if it fails, say so.
