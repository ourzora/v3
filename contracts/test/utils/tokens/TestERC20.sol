// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title TestERC20
/// @notice FOR TEST PURPOSES ONLY.
contract TestERC20 is ERC20 {
    constructor() ERC20("TestERC20", "TEST") {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
