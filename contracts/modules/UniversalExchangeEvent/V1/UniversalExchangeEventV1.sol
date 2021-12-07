// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title UniversalExchangeEvent V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module generalizes indexing of all token exchanges across the protocol
contract UniversalExchangeEventV1 {
    /// @notice A ExchangeDetails object that tracks a token exchange
    /// @member tokenContract The address of the token contract
    /// @member tokenId The id of the token
    /// @member amount The amount of tokens being exchanged
    struct ExchangeDetails {
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
    }

    event ExchangeExecuted(address indexed userA, address indexed userB, ExchangeDetails a, ExchangeDetails b);
}
