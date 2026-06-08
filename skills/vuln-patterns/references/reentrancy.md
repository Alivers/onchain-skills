# Reentrancy

A function makes an external call before it finishes updating its own state, so the
callee can call back in and act on stale state. A violation of CEI
(Checks-Effects-Interactions).

## Heuristic (the smell)

- An external interaction — `addr.call{value:}`, `token.transfer` of a
  hook-bearing token (ERC777/ERC677), an ERC721 `safeTransfer`'s `onERC721Received`,
  or any callback to a user-controlled address — happens **before** the balance/flag
  it depends on is written.
- `nonReentrant` is absent, or present on the entry function but not on a sibling
  that shares the same state (cross-function), or the state is read by a *view* that
  another protocol trusts (read-only).

## Variants

- **Single-function:** classic withdraw that zeroes the balance after sending.
- **Cross-function:** `withdraw()` is guarded but `transfer()` mutates the same
  ledger and isn't, so you re-enter through the unguarded sibling.
- **Cross-contract:** two contracts share state via a third; the guard on one
  doesn't cover the path through the other.
- **Read-only reentrancy:** during your callback, a `view` (e.g. `get_virtual_price`,
  LP price) returns an inconsistent value, and a *different* protocol prices off it.
  No state is written by you — you exploit the half-updated state another contract reads.
- **Token-hook reentrancy:** ERC777 `tokensReceived` / ERC721 `onERC721Received`
  give the attacker control mid-transfer even when the protocol "only moves tokens".

## Where to look

Withdraw/claim/redeem paths, anything sending native ETH, integrations with
ERC777 tokens, NFT mints/escrows using `safeTransfer`, and *view* functions other
protocols consume as oracles.

## Minimal PoC sketch

See the fully-runnable example at `test/examples/Reentrancy.t.sol`. Shape:

```solidity
function pwn() external payable { vault.deposit{value: 1 ether}(); vault.withdraw(); }
receive() external payable {                       // re-enter while balance still set
    if (address(vault).balance >= 1 ether) vault.withdraw();
}
```

For read-only reentrancy the attacker contract does nothing malicious in the
callback except call the *victim* (the third protocol) that reads the stale view.

## Fixes (to recognize a safe target)

CEI ordering (effects before interactions), `ReentrancyGuard`/`nonReentrant`
covering every function touching the shared state, pull-over-push payments, and
guards on the *view* functions used as price sources (or a reentrancy-lock check).

## Real-world cases

The DAO (2016), Cream Finance (ERC777), Curve/JPEG'd and others (read-only
reentrancy via `get_virtual_price`), Rari/Fei, Siren.
