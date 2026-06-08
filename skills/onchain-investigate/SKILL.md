---
name: onchain-investigate
description: Use this when someone wants an EVM hack or exploit taken from start to finish: understand what happened AND prove it with a working proof-of-concept. The defining signal is scope — they want the whole job (decode the tx, study the contracts, name the bug, reproduce it in a forge test that matches the real loss), not a single isolated step. Trigger for: post-mortems of a hack or drain, "investigate this attack end to end", "figure out how this was exploited and reproduce it", "complete/full analysis of this exploit", "find and prove a vulnerability in this contract", or a hack report/news link plus a tx hash and victim address to dig into. Also "复盘攻击", "查清这次被黑", "端到端分析". The give-away words are end-to-end, reproduce, prove, PoC, root cause, post-mortem combined with an investigation. If they only want one step — just decode a tx, just recon an address, or a high-level explanation with no reproduction — use the focused skill instead, not this one. It orchestrates tx-decoder → contract-recon → vuln-patterns → forge-poc and stops when a green PoC matches reality.
---

# onchain-investigate

The conductor. A real investigation isn't one tool call — it loops between
understanding and proving until a runnable PoC reproduces what actually happened.
This skill sequences the four focused skills and keeps the loop honest; it does not
duplicate their mechanics — defer to each for the how.

| Step | Skill | Produces |
|---|---|---|
| Understand the tx | `tx-decoder` | call tree, value flow, first hypothesis |
| Understand the code | `contract-recon` | source/interface, proxy→impl, owner, attack surface |
| Name the bug | `vuln-patterns` | vuln class(es), mechanics, PoC shape |
| Prove it | `forge-poc` | a passing fork test = ground truth |

## Pick the entry point

**A. A transaction happened (post-mortem of a hack):**
1. `tx-decoder` on the attack tx → call tree, net value flow, who profited, a first
   guess at the primitive. Note the **block** (you'll fork at `block - 1`).
2. `contract-recon` on each contract the trace leans on (the victim, any proxy, the
   manipulated pool/oracle) → real implementation, owner/admin, the function the
   attack abused, its (missing) guard.
3. `vuln-patterns` → name the class **and what it's chained with** (most hacks stack
   2–4 primitives; don't stop at the first match).
4. `forge-poc` → fork at `block - 1`, replay the attacker's steps from a clean EOA,
   assert profit. **Convergence:** the PoC's profit/invariant-break matches the real
   tx. If it doesn't, the hypothesis is wrong — go back to step 1/3.

**B. Just an address (bug-bounty / proactive):**
1. `contract-recon` → attack surface, control, integrations.
2. `vuln-patterns` → walk *Where to look first* against the surface; form ranked
   hypotheses by reasoning from invariants, not keyword matching.
3. `forge-poc` → fork a recent block, fund a clean attacker, try to break the top
   hypothesis. Green = a real finding; red = cross it off and take the next one.
4. Loop step 3 down the ranked list until something proves out or the list is dry.

## The loop, not a line

Investigation is iterative. A failed PoC is **information**: it refutes a hypothesis
and usually points at the missing piece (a guard you overlooked, a second primitive,
the wrong block, a token quirk). Expect to bounce decode ⇄ recon ⇄ poc several times.
Don't force a tidy single pass.

## Convergence criteria (when to stop)

- **Post-mortem:** a green `forge-poc` whose extracted value (and ideally the trace
  shape) matches the real attack. Then you understand it.
- **Bounty:** a green `forge-poc` that breaks a real invariant from a clean starting
  state with no special privileges. Then it's a finding worth reporting.
- Stop also when the ranked hypotheses are exhausted and nothing proves out — report
  that honestly rather than manufacturing a story.

## Output: investigation report

```
Target:        <protocol> — <address(es)> on <chain>
Trigger:       <attack tx hash | "bounty recon"> @ block <N>
What happened: <2–4 sentences: actors, money flow, the broken invariant>
Root cause:    <vuln class(es), chained how>
Reproduction:  <PoC file> — forked <chain>@<block-1>, asserts <profit/invariant>,
               result: PASS, extracted <amount> (matches real loss of <amount>)
Fix:           <what would have prevented it>
```

## Honesty (load-bearing)

Every claim downstream rests on the PoC. Until `forge-poc` is green, the narrative is
a hypothesis — say so. Report failed hypotheses and unresolved gaps; a partial,
honest investigation beats a confident wrong one. Never present an unreproduced
theory as the confirmed root cause.
