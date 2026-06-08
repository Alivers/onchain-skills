# onchain-skills

Claude Code skills for analyzing **EVM on-chain contract vulnerabilities** — built
for post-mortem reproduction of hacks, bug-bounty PoCs, and teaching.

Distributed as a **Claude Code plugin**. The repo is also a ready-to-use Foundry
workspace, so you can `git clone` and start writing PoCs immediately.

## Skills

| Skill | Layer | What it does | Status |
|---|---|---|---|
| `forge-poc` | L1 | Fork a chain at a block, write & run a Foundry PoC to reproduce/validate an exploit | ✅ |
| `cast-inspect` | L1 | Read storage/state, replay & trace txs, decode calldata with `cast` | ⬜ planned |
| `tx-decoder` | L2 | One tx hash → call tree + decoded calldata/events + "what happened" | ⬜ planned |
| `contract-recon` | L2 | One address → source/decompile + proxy detection + attack surface | ⬜ planned |
| `vuln-patterns` | L3 | Library of historical vuln classes: heuristics + minimal PoC templates | ⬜ planned |
| (orchestrator) | L4 | address/tx → recon → decode → hypothesize → PoC → verify | ⬜ planned |

## Install as a plugin

```
/plugin marketplace add Alivers/onchain-skills   # or a local path: /plugin marketplace add .
/plugin install onchain-skills
```

When a skill runs inside a project that isn't a Foundry workspace, `forge-poc`
bootstraps `foundry.toml` + the `PoCTest` base from the plugin root and runs
`forge install`.

## Use directly (clone the workspace)

```
git clone <this-repo> && cd onchain-skills
forge install foundry-rs/forge-std     # lib/ is gitignored
cp .env.example .env                    # fill in archive RPCs + Etherscan V2 key
forge test                              # runs the self-contained example PoCs
```

## Setup notes

- **Archive RPCs required** for forking historical blocks (Alchemy/Infura/self-host).
  Public RPCs only keep recent state and fail with `missing trie node`.
- **Etherscan V2**: a single API key works across all chains (`ETHERSCAN_API_KEY`).
- Chains/aliases live in [foundry.toml](foundry.toml) `[rpc_endpoints]` — add more there.

## Layout

```
.claude-plugin/      plugin.json + marketplace.json
skills/              one dir per skill (SKILL.md)
test/base/           PoCTest.sol — shared base for exploit PoCs
test/examples/       self-contained teaching PoCs (run with no RPC)
foundry.toml         multi-chain RPC + Etherscan config
```
