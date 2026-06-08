---
name: contract-recon
description: Reconnaissance on a deployed EVM contract address — fetch its source (or recover an interface when unverified), detect proxy patterns and resolve the real implementation, find the owner/admin/roles, and map the externally-callable attack surface. Use this whenever you have a contract ADDRESS and need to understand it before attacking or auditing: "what does this contract do", an unverified/proxy contract a tx-decoder trace pointed at, scoping a bug-bounty target, finding who controls it, listing its state-changing functions, or recovering an ABI/interface to call in a PoC. Triggers: "analyze this contract", "is this a proxy", "what's the implementation", "recover the ABI", "unverified contract", "attack surface of 0x…", "这个合约是干嘛的", "代理合约", "看下这个地址". For a single transaction use tx-decoder; to prove a finding use forge-poc.
---

# contract-recon

Turn a bare address into a map you can attack from: source/interface, proxy →
implementation, who controls it, and the externally-reachable functions worth
probing. This is the static counterpart to tx-decoder (which is per-tx); both feed
`forge-poc`.

## Prerequisites

- RPC for the contract's chain (foundry.toml alias).
- `ETHERSCAN_API_KEY` (V2, one key all chains) for source/ABI fetch.
- Optional but great for **unverified** contracts:
  [`heimdall`](https://github.com/Jon-Becker/heimdall-rs) (`heimdall decompile`).

## Workflow

### 1. Is it even a contract? Which kind?
```bash
cast code <addr>     --rpc-url <alias>   # 0x = EOA (stop), else runtime bytecode
cast codesize <addr> --rpc-url <alias>   # tiny size (~45 bytes) hints a minimal proxy
```

### 2. Proxy detection — find the code that actually runs
Most targets are proxies; the address you have holds storage but delegatecalls logic
elsewhere. Resolve it before reading anything:
```bash
cast implementation <addr> --rpc-url <alias>   # EIP-1967 impl slot (or beacon)
cast admin          <addr> --rpc-url <alias>   # EIP-1967 admin slot
```
- Non-zero implementation → **recon the implementation address** for logic, but keep
  the proxy address for state/storage. Note the admin (it can upgrade — an attack path).
- Minimal proxy (EIP-1167): bytecode like `363d3d373d3d3d363d73<impl>5af43d82803e…`
  — the impl is embedded in the bytecode.
- Also possible: UUPS (impl holds upgrade logic), Beacon, Diamond (EIP-2535, many
  facets — enumerate via `facets()`/loupe). If `cast implementation` is zero but the
  contract clearly delegates, check these.

### 3a. Verified → pull source & interface
```bash
cast source    <impl_or_addr> -d out/recon/<addr>   # full source tree
cast interface <impl_or_addr> -o out/recon/<addr>.sol   # Solidity interface from ABI
```
Read the source; jump to step 4.

### 3b. Unverified → recover the surface
```bash
# Extract function selectors AND resolve their signatures (via openchain):
cast selectors "$(cast code <addr> --rpc-url <alias>)" --resolve
# Full decompilation to pseudo-Solidity + recovered ABI:
heimdall decompile <addr> --rpc-url <alias> -o out/recon/<addr>
# Raw opcodes if you need to read a specific path:
cast disassemble "$(cast code <addr> --rpc-url <alias>)"
```
`cast selectors --resolve` alone usually gives enough to call functions in a PoC.
For a human, dedaub.com's decompiler is the nicest UI (don't scrape it — link it).

### 4. Who controls it?
```bash
cast call <addr> "owner()(address)"        --rpc-url <alias>
cast call <addr> "admin()(address)"        --rpc-url <alias>
cast call <addr> "getRoleAdmin(bytes32)(bytes32)" <role> --rpc-url <alias>
cast call <addr> "paused()(bool)"          --rpc-url <alias>
```
Plus the EIP-1967 admin from step 2. Unverified owner? Read likely slots with
`cast storage <addr> <slot>`. Privileged control = both an attack target (can it be
hijacked?) and a thing to neutralize in a PoC (`vm.prank(owner)`).

### 5. Map the attack surface
From the source/decompiled functions, list:
- **State-changing external/public functions** and the auth guard on each (none?
  wrong modifier? `tx.origin`?).
- **Value flows** — which functions move tokens/ETH in or out.
- **External calls & delegatecalls** — to whom; user-controlled targets?
- **Price/amount derivations** — any spot read from a pool (oracle risk).
- **Upgrade/admin paths** — initializer guarded? admin a multisig or an EOA?

Cross-reference each against `vuln-patterns` *Where to look first* to turn the map
into ranked hypotheses — then prove the top one with `forge-poc`.

## Output: recon report

Produce a compact report, not a code dump:

```
Address:        0x… (<chain>)
Type:           <EOA | contract | EIP-1967 proxy | minimal proxy | diamond>
Implementation: 0x…  (verified? Y/N)
Admin / owner:  0x…  (EOA / multisig / timelock)  — can upgrade: Y/N
Key functions:  fn(args)  guard=<onlyOwner|none|…>  moves=<token/ETH>
                …
Integrations:   <pools, oracles, external contracts called>
Candidate vulns: <ranked classes from vuln-patterns, with why>
Next:           <the one hypothesis to take to forge-poc>
```

## Gotchas

- Reading the proxy address's "source" gives proxy boilerplate, not the logic —
  always resolve the implementation first.
- Diamonds split logic across facets; one `cast source` won't show everything.
- `owner()` reverting doesn't mean no owner — control may be a role, an admin slot,
  or a separate governance contract. Keep digging.
- Decompiled names are inferred/guessed; verify behavior against the bytecode or a
  fork call before relying on them.
