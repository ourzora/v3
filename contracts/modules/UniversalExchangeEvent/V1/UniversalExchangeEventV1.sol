// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

/// @title UniversalExchangeEvent V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module generalizes indexing of all token exchanges across the protocol
contract UniversalExchangeEventV1 {
    /// @notice A ExchangeDetails object that tracks a token exchange
    /// @member tokenContract The address of the token contract
    /// @member tokenID The ID of the token
    /// @member amount The amount of tokens being exchanged
    struct ExchangeDetails {
        address tokenContract;
        uint256 tokenID;
        uint256 amount;
    }

    event ExchangeExecuted(address indexed userA, address indexed userB, ExchangeDetails a, ExchangeDetails b);
}
