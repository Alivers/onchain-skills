# Vault Share Inflation (First-Deposit / Donation)

A share-based vault (ERC4626 and look-alikes) can be set up so a victim's deposit
mints **zero** shares, letting the attacker withdraw the victim's assets. Driven by
integer rounding plus a direct token donation.

## Heuristic (the smell)

- Shares are minted as `shares = assets * totalSupply / totalAssets` (or
  `assets * totalSupply / token.balanceOf(vault)`), with **no** virtual shares/offset
  and **no** minimum-deposit or dead-shares protection.
- `totalAssets()` is `token.balanceOf(address(this))` — i.e. it counts **donated**
  tokens, not just deposited ones.
- Empty-vault path: first depositor gets `shares = assets` but nothing stops them
  from then inflating `totalAssets` without minting shares.

## Where to look

Freshly deployed ERC4626 vaults / yield aggregators / LP wrappers, any
`convertToShares`/`previewDeposit` using raw `balanceOf`, forks of vault code that
stripped the OZ virtual-offset.

## Exploit mechanics

1. Be the first depositor: deposit 1 wei → mint 1 wei of shares (totalSupply = 1).
2. **Donate** a large amount of the asset directly to the vault (plain `transfer`,
   no mint). Now 1 share is "worth" the whole donation.
3. Victim deposits `X`. Their shares = `X * 1 / (donation + 1)` which **rounds down
   to 0**. They get nothing; their assets are now backing the attacker's 1 share.
4. Attacker redeems 1 share for the entire pool (donation + victim deposit).

## Minimal PoC sketch

```solidity
function test_inflateShares() public {
    vault.deposit(1, address(this));                 // 1 wei -> 1 share
    asset.transfer(address(vault), 10_000e18);        // donation inflates price
    // victim deposits; rounds to 0 shares
    vm.prank(victim);
    uint256 got = vault.deposit(9_999e18, victim);
    assertEq(got, 0, "victim should be griefed to 0 shares");
    vault.redeem(1, address(this), address(this));    // attacker takes everything
    assertGt(asset.balanceOf(address(this)), 10_000e18);
}
```

## Fixes (to recognize a safe target)

OZ ERC4626 virtual shares + decimals offset, minting "dead shares" to address(0) at
deploy, a minimum first deposit, or tracking deposited assets internally instead of
`balanceOf` (so donations don't count).

## Real-world cases

Numerous ERC4626 fork incidents and audit findings; the canonical "first depositor /
donation" attack discussed widely after early Yield/Rari-style vaults.
