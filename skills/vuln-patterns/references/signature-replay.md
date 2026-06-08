# Signature Replay / Forgery

Off-chain signatures authorize on-chain actions, but the signed message is missing
a binding that makes it single-use and context-specific, so it can be replayed or
forged.

## Heuristic (the smell)

- `ecrecover(...)`-based auth (or `permit`, meta-tx, claim, order) where the signed
  digest lacks one of: a **nonce**, a **deadline/expiry**, the **chainId**, the
  contract **address** (domain separator), or the specific **amount/target**.
- No tracking of used signatures (`mapping(bytes32 => bool) used`), so the same sig
  works twice.
- Raw `ecrecover` without checking `s` is in the lower half-order (malleability) or
  without rejecting `signer == address(0)`.
- A domain separator computed once and cached across a chain fork (no chainId in it).

## Where to look

`permit`/EIP-2612, meta-transactions/relayers, airdrop/merkle claims with a backend
signature, off-chain order books (NFT/DEX), gasless approvals, multisig confirmations.

## Exploit mechanics

- **Replay:** capture a valid signature and submit it again (same contract second
  time, or on another chain / a forked deployment if chainId/address aren't bound).
- **Forgery via malleability:** given `(r,s,v)`, produce `(r, n-s, v')` — a different
  valid signature for the same message, bypassing a naive "seen this exact sig" check.
- **Cross-context:** a signature meant for contract A is accepted by contract B
  because the domain separator isn't bound to the address.

## Minimal PoC sketch

```solidity
function test_replay() public {
    bytes memory sig = _ownerSig(amount, recipient);   // a legitimately captured sig
    target.claimWithSig(amount, recipient, sig);         // first use: ok
    target.claimWithSig(amount, recipient, sig);         // replay: should revert, but doesn't
    assertEq(token.balanceOf(recipient), amount * 2, "claimed twice");
}
```

## Fixes (to recognize a safe target)

EIP-712 typed data with a domain separator that includes `chainId` + `verifyingContract`,
a per-signer nonce that increments on use, a `deadline`, marking digests used, and
`ECDSA.tryRecover` (OZ) which rejects malleable `s` and zero address.

## Real-world cases

Various permit/airdrop replay incidents, signature malleability bugs, and
cross-chain replay where a redeployed contract shared a cached domain separator.
