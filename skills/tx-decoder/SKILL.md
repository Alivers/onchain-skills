---
name: tx-decoder
description: Decode and explain an EVM transaction using `cast` — reconstruct its full call tree, decode calldata/events/errors, follow the token value flow, and narrate what actually happened (dedaub/Phalcon-style), ending in a vulnerability hypothesis. Use this whenever the user pastes a tx hash and asks what it did, wants to analyze or dissect an attack/exploit transaction, trace internal calls, decode an unknown 4-byte selector or raw calldata, figure out who profited, or understand a hack before reproducing it — even a bare 0x… hash with no other words should trigger this. This is the read-only front half of a post-mortem; once the goal becomes proving/reproducing the exploit in code, hand off to forge-poc. Triggers: "what did this tx do", "decode this transaction", "analyze this attack tx", "trace this exploit", "解析这笔交易", "这笔交易做了什么", "这笔攻击怎么回事", a bare transaction hash.
---

# tx-decoder

Given a transaction hash, reconstruct what actually happened: the call tree, the
decoded inputs/events, the money flow, and a plain-language narrative ending in a
vulnerability hypothesis. This is the **read-only** front half of a post-mortem;
`forge-poc` is the back half that reproduces it.

Everything here runs locally with `cast` against an RPC — no dedaub/Phalcon needed,
though they're fine cross-checks.

## Prerequisites

- An RPC for the tx's chain (foundry.toml alias, e.g. `mainnet`, `bsc`). For deep
  internal traces this should be an **archive** node.
- `ETHERSCAN_API_KEY` (V2, one key all chains) so `cast` auto-fetches verified
  source/ABIs and labels contracts in the trace. Without it, traces show raw
  selectors and unlabeled addresses.

## Workflow

### 1. Skeleton — what/where, in 2 commands
```bash
cast tx <txhash>      --rpc-url <alias>   # from, to, value, input, block, nonce
cast receipt <txhash> --rpc-url <alias>   # status (1=ok), gas used, logs, contracts created
```
Note the **block number** — you'll fork at `block - 1` later. Status 0 = reverted
(still worth tracing: many probes/failed attacks revert).

### 2. Full call tree — the core step
```bash
cast run <txhash> --rpc-url <alias> --decode-internal --quick
# ETHERSCAN_API_KEY in env → contracts named & calls decoded automatically
```
- `--decode-internal` resolves internal function calls (not just external CALLs).
- `--with-local-artifacts` decodes using this Foundry project's compiled contracts —
  use it after you've written interfaces/mocks so your names show up.
- `--label <addr>:<name>` to tag known actors (attacker, pool, victim) for readability.
- Read the trace **top-down**: each indentation level is a deeper CALL. Look for the
  call that does the unexpected thing (mints, transfers out, sets a price, etc.).

### 3. Decode anything the trace left raw
```bash
cast 4byte <selector>                          # unknown function selector → signature(s)
cast decode-calldata "<sig>" <calldata>        # calldata → typed args
cast 4byte-event <topic0>                       # unknown event topic → signature
cast decode-event --sig "<EventSig>" <data>     # event data → typed args
cast decode-error <data>                         # custom revert error → decoded
cast pretty-calldata <calldata>                  # last resort: guess structure
```
4byte/openchain can return multiple candidates — pick the one consistent with the
arg types and surrounding trace.

### 4. Follow the money — build a value ledger
```bash
# All Transfer(address,address,uint256) logs in the tx's block, filtered to actors:
cast logs --rpc-url <alias> --from-block <blk> --to-block <blk> \
  "Transfer(address,address,uint256)" --address <token>
```
From the receipt's logs, decode every `Transfer` / `Swap` / `Deposit` / `Withdraw`
and tabulate net token deltas per address. The attacker is whoever ends up net
positive in value. Flag flash-loan shape: large borrow at the start, repay at the end.

### 5. Narrate + hypothesize
Produce, in this order:
1. **Actors** — attacker EOA, attacker contract, victim/protocol, pools touched.
2. **Money flow** — net deltas; how much was extracted and in what token.
3. **The primitive** — the single call/sequence that broke an invariant (price
   manipulation, reentrancy, missing access control, bad accounting, etc.).
4. **Vuln class hypothesis** — name it; cross-reference the `vuln-patterns` library.

### 6. Hand off to forge-poc
End every attack analysis by setting up reproduction: fork the chain at
`block - 1`, replay the attacker's steps, and confirm the same net profit. A
matching trace + profit means the analysis is correct, not just plausible.

## Web explorers — emit for the human, don't scrape

Hosted decoders (dedaub, Phalcon, Tenderly, openchain) have far nicer call-tree /
state-diff / gas UIs than a terminal. But they are JS SPAs: a headless `WebFetch`
of their tx URL returns an empty shell, not the trace — **do not try to read the
analysis off these pages.** Their value is for the *human*. So:

- **`cast` stays the analysis engine** (parseable text → feeds `forge-poc`).
- **Emit a link or two** in the output so the user can open the rich UI and
  cross-check your narrative. Build them from the tx hash (verify the path scheme
  is current before trusting it — these change):
  - **Phalcon (BlockSec)** — best call-tree + state diff + balance changes:
    `https://app.blocksec.com/explorer/tx/<chain>/<txhash>` (chain: `eth`, `bsc`,
    `arbitrum`, `optimism`, `base`, `polygon`, …)
  - **openchain trace** — free, fast, no login:
    `https://openchain.xyz/trace/<chain>/<txhash>`
  - **dedaub** — strong decompiler + tx viewer for unverified contracts.
  - **Tenderly** — debugger + simulator; unlike the others it has a **JSON API**,
    so if the user has a Tenderly token you *can* pull a structured trace
    programmatically (the one web tool worth calling from the skill).
- Reach for them when cast labels are sparse (unverified/proxy-heavy txs), when you
  need gas profiling, or simply to hand the user something clickable.

## Tips & gotchas

- **Wrong chain** → `cast run` produces garbage or errors. Confirm the chain first
  (the explorer URL the user pasted usually says it).
- **Reverted tx** still traces — use it to see how far an attacker's probe got.
- **Unverified contracts** show only selectors. For those, use the `contract-recon`
  skill (decompile / storage-layout inference) before continuing.
- **Proxies**: the trace shows the proxy address but executes implementation logic;
  `cast implementation <proxy>` (EIP-1967) reveals the logic contract to fetch source for.
- Cross-check a tricky trace against dedaub.com / Phalcon explorer, but the cast
  trace + a green `forge-poc` is the ground truth.

## Honesty

Report what the trace actually shows. If a selector is unresolved or a value path is
ambiguous, say so rather than inventing a clean story. The narrative is a hypothesis
until `forge-poc` reproduces it.
