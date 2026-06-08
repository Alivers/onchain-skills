# Delegatecall / Proxy Storage

`delegatecall` runs another contract's code against **this** contract's storage. When
the two disagree on storage layout — or when an implementation is reachable directly
— state gets corrupted or hijacked.

## Heuristic (the smell)

- A proxy and its implementation declare state variables in **different orders**, or
  the proxy adds variables before the implementation's (slot collision). EIP-1967
  slots exist precisely to avoid this — their absence is a flag.
- An implementation contract behind a proxy is **not** initialized and has an
  `initialize()` plus a `selfdestruct`/`delegatecall` reachable by anyone.
- `delegatecall` to an address the caller controls (arbitrary code as the contract).
- Function selector clashes between proxy and implementation (a proxy admin function
  shadows an implementation function, or vice versa).
- Upgradeable contract missing storage gaps (`uint256[50] __gap`) so a V2 that adds
  vars collides with child storage.

## Where to look

Proxy admin/upgrade logic, `initialize` guards on the **implementation** (not just
the proxy), libraries called with `delegatecall`, anything taking a `target` address
for `delegatecall`, and storage layout diffs across upgrades.

## Exploit mechanics

- **Uninitialized implementation:** call `initialize()` on the logic contract
  directly to own it, then trigger its `selfdestruct` (or a `delegatecall` to your
  code) — bricking every proxy that delegatecalls into it.
- **Storage collision:** a variable you can write in the implementation overlaps the
  proxy's `admin`/`owner` slot, so writing a "balance" overwrites the admin.
- **Arbitrary delegatecall:** point it at a contract whose code does
  `selfdestruct`/ownership change executed in the victim's context.

## Minimal PoC sketch

```solidity
function test_uninitializedImpl() public {
    LogicV1 impl = LogicV1(IMPLEMENTATION_ADDR);     // the logic behind the proxy
    impl.initialize(address(this));                   // never guarded -> we own the impl
    impl.kill();                                       // selfdestruct in impl context
    // every proxy delegatecalling into impl now reverts (funds frozen)
}
```

## Fixes (to recognize a safe target)

EIP-1967 / OZ `TransparentUpgradeableProxy` or `UUPSUpgradeable`,
`_disableInitializers()` in the implementation constructor, storage gaps, no
user-controlled `delegatecall` targets, and `forge inspect <C> storage-layout` to
diff layouts across upgrades.

## Real-world cases

Parity multisig second incident (uninitialized library `kill` froze ~$150M),
numerous upgradeable-contract storage-collision bugs.
