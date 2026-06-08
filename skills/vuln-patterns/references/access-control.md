# Access Control

A state-changing function that should be restricted isn't — or is restricted the
wrong way. Simple, common, and often catastrophic.

## Heuristic (the smell)

- A sensitive function (`mint`, `withdraw`, `setOwner`, `upgradeTo`, `pause`,
  `setOracle`, sweep/rescue) is `public`/`external` with **no** `onlyOwner`/role check.
- An `initialize()` (proxy pattern) is callable by anyone, or callable **twice**
  (no `initializer` guard / no `_disableInitializers` in the implementation).
- Auth uses `tx.origin == owner` (phishable) instead of `msg.sender`.
- The owner/admin is never set (defaults to `address(0)`) or can be set by anyone.
- A modifier exists but is on the wrong function, or checks the wrong role.
- `delegatecall` to a user-supplied address (lets the caller run arbitrary code as
  the contract — effectively total access-control loss).

## Where to look

Every externally-callable function that changes ownership, money, upgrade targets,
oracle/parameters, or pausing. Proxy `initialize` functions and their guards.
Constructors vs initializers (logic in constructor doesn't run for proxies).

## Exploit mechanics

Usually a single direct call: front-run or simply call the unprotected
`initialize()` to become owner, then drain/upgrade; or call the unguarded
privileged function directly. With `tx.origin` auth, lure the owner into a
malicious contract that calls through.

## Minimal PoC sketch

```solidity
function test_stealOwnership() public {
    // implementation/proxy was deployed but never initialized
    target.initialize(address(this));            // no guard -> we are now owner/admin
    assertEq(target.owner(), address(this));
    target.setOracle(address(evilOracle));        // now do anything privileged
    target.sweep(token, address(this));
}
```

## Fixes (to recognize a safe target)

`Ownable`/`AccessControl` with correct roles, OZ `Initializable` +
`_disableInitializers()` in the implementation constructor, `msg.sender` (never
`tx.origin`), two-step ownership transfer, and constructor-set immutable admins.

## Real-world cases

Parity multisig (`initWallet` callable by anyone), countless unprotected
`initialize()` takeovers, Audius (proxy/init), and many "rescue"/"sweep" functions
left public.
