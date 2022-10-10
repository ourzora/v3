// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IVariableSupplyAuction} from "./IVariableSupplyAuction.sol";

/// @title Variable Supply Auction
/// @author neodaoist
/// @notice Module for variable supply, seller's choice, sealed bid auctions in ETH for ERC-721 tokens
contract VariableSupplyAuction is IVariableSupplyAuction {
    //
    function hello() public pure returns (bytes32) {
        return bytes32("hello world");
    }
}
