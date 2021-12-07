// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "hardhat/console.sol";

contract SimpleModule {
    function ok() public pure returns (uint256) {
        return 1;
    }
}
