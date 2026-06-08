---
name: chain-access
description: Set up and diagnose RPC + block-explorer access for on-chain analysis — test whether an endpoint is archive, pick the cheapest way to get a transaction trace, work around rate limits, and configure foundry.toml/.env for any chain. Use this the moment fork/trace/state work misbehaves: "missing trie node", "historical state not available", a `cast run` that won't replay, 429 / rate-limit errors, "is this RPC archive", "which BSC/L2 archive endpoint should I use", picking `debug_traceTransaction` vs `cast run`, or wiring up a new chain's RPC and Etherscan key. Triggers: "missing trie node", "is this archive", "rate limited", "can't fork at this block", "trace this tx but cast run fails", "setup RPC", "配置节点", "这个 rpc 是 archive 吗", "节点限流". The focused skills (tx-decoder/forge-poc) assume access already works; reach here when it doesn't.
---

# chain-access

Every fork, replay, and historical read depends on the RPC being good enough. Most
"the tool is broken" moments are really "the endpoint can't serve what I asked."
This skill makes access a solved problem before you waste time on it.

## Is this endpoint archive? (one probe)

Forking/replaying a historical block needs **archive** state. Free public nodes are
almost always pruned (only ~recent blocks). Test in one call:

```bash
cast balance 0xAnyAddress --block <oldBlock> --rpc-url <url>
```
- Returns a number → archive has that block's state ✓
- `missing trie node` / `historical state ... is not available` → **pruned, not archive** ✗

Pick `<oldBlock>` well behind head (e.g. head − 1,000,000, or your target block). If it
fails even on the block you care about, that endpoint can't fork there — stop and switch.

## Getting a trace cheaply (this matters under rate limits)

Two ways to reconstruct a tx's call tree — wildly different RPC cost:

| Method | How | RPC cost | Use when |
|---|---|---|---|
| `cast run <tx>` | re-executes the tx **locally**, lazily fetching every account/slot it touches | **heavy** — hundreds–thousands of requests | you have a generous archive key; want full `vm`-style trace + labels |
| `debug_traceTransaction` + `callTracer` | the **node** computes the call tree, returns it in **one** response | **1 request** | rate-limited / free tier; you just need who-called-what |

```bash
# Node-side, one shot (prefer this on a throttled key):
cast rpc debug_traceTransaction <tx> '{"tracer":"callTracer"}' --rpc-url <url> > tree.json
# Parity-style nodes instead expose:
cast rpc trace_transaction <tx> --rpc-url <url>
```
If `cast run` keeps 429-ing, switch to `callTracer` first — it sidesteps the storage-fetch
storm entirely. (Not every provider enables `debug_*`/`trace_*` on free tiers; if it errors
with "method not allowed", that tier gates tracing.)

## Rate limits (429) — three levers, in order

1. **Throttle cast's own request rate** so it stays under the burst cap:
   `cast run <tx> --rpc-url <url> --compute-units-per-second 4 --rpc-timeout 60`
2. **Warm the cache across retries.** Foundry caches fetched fork state on disk
   (`~/.foundry/cache/rpc/<chain>/<block>`). Re-running `cast run` reuses cached
   slots and makes fewer live calls — the failure point should advance each run. If
   it stops advancing and every call 429s immediately, you've hit a **cumulative**
   usage cap (not a per-second one) — throttling won't help, only a better key will.
3. **Prefer the 1-request `callTracer`** over local replay (see above).

## Providers (what actually serves archive + trace)

- **Free public bare endpoints are pruned** — `publicnode`, `llamarpc`, dataseeds,
  keyless `nodereal` — fine for `cast tx`/`receipt`/`logs` (no historical state), useless
  for replay. Don't fight them.
- **Archive + trace needs a keyed endpoint:** QuickNode, Alchemy, Chainstack,
  NodeReal MegaNode (BSC-strong), BlockPI, GetBlock. BSC archive is ~20TB+, so it's
  effectively paid/keyed; free tiers exist but cap usage (a full `cast run` can exhaust them —
  use `callTracer`).
- **Etherscan V2:** one API key works across all chains via `chainid` — set it once
  as `ETHERSCAN_API_KEY`; `cast`/`forge` use it for source/ABI/labels.

## Wiring it up (this repo's foundry.toml)

Add chains under `[rpc_endpoints]` (alias = `${VAR}`) and `[etherscan]` (with chainid),
put the real URLs/keys in `.env` (gitignored — never commit). Verify:
```bash
cast block-number --rpc-url <alias>   # alias resolves from foundry.toml + .env
cast balance 0x... --block <old> --rpc-url <alias>   # archive probe
```

## Troubleshooting map

| Symptom | Cause | Fix |
|---|---|---|
| `missing trie node` / `historical state not available` | endpoint is pruned, not archive | use a keyed archive endpoint |
| `429` mid-`cast run`, failpoint advances | per-second burst cap | `--compute-units-per-second`, retry to warm cache |
| `429` immediately, every call | cumulative usage cap exhausted | wait for reset, or upgrade/switch key |
| `tx not found` | wrong chain, or node lagging head | confirm chain; try another provider |
| `method debug_traceTransaction does not exist` | trace gated on this tier | use a provider/tier that enables `debug_*` |
| source/labels missing in trace | no `ETHERSCAN_API_KEY` | set the V2 key in `.env` |

## Honesty

If access is the blocker, say so plainly and name what's needed (archive? trace
method? a paid key?) — don't pass off a half-fetched or unlabeled result as a complete
analysis. The cheapest unblock is usually a single `callTracer` call on an adequate key.
