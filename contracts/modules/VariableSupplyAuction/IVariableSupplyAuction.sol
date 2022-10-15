// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IVariableSupplyAuction
/// @author neodaoist
/// @notice Interface for Variable Supply Auction
interface IVariableSupplyAuction {
    //

    ///
    function createAuction(
        uint256 _minimumRevenue,
        address _sellerFundsRecipient,
        uint256 _startTime,
        uint256 _bidPhaseDuration,
        uint256 _revealPhaseDuration,
        uint256 _settlePhaseDuration
    ) external;
}
