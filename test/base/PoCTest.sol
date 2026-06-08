// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @title PoCTest
/// @notice Base class for on-chain exploit PoCs. Handles forking and gives a
///         few helpers that make a PoC read like an attack narrative.
///
/// Usage:
///   contract MyExploit is PoCTest {
///       function setUp() public { _fork("mainnet", 19_000_000); }
///       function test_exploit() public { ... }
///   }
abstract contract PoCTest is Test {
    /// @notice Fork a chain at a specific block. ALWAYS pin the block so the
    ///         PoC is deterministic — for post-mortems use (attack_block - 1)
    ///         to reproduce the pre-attack state.
    /// @param chainAlias rpc_endpoints key from foundry.toml (e.g. "mainnet")
    /// @param blockNumber block to fork at
    function _fork(string memory chainAlias, uint256 blockNumber) internal {
        vm.createSelectFork(vm.rpcUrl(chainAlias), blockNumber);
    }

    /// @notice Fork at the latest block (non-deterministic; prefer pinning).
    function _fork(string memory chainAlias) internal {
        vm.createSelectFork(vm.rpcUrl(chainAlias));
    }

    /// @notice Give `who` a labeled identity in traces.
    function _actor(string memory name) internal returns (address who) {
        who = makeAddr(name);
    }

    /// @notice Print an ERC20 balance line for the exploit ledger.
    function _logBalance(string memory label, address token, address who) internal view {
        (bool ok, bytes memory ret) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        uint256 bal = ok && ret.length >= 32 ? abi.decode(ret, (uint256)) : 0;
        console.log(label, bal);
    }
}
