// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

contract UniversalExchangeEventV1 {
    struct ExchangeDetails {
        address tokenContract; // Address of the token contract
        uint256 tokenID; // (Optional) tokenID being exchanged
        uint256 amount; // (Optional) The amount of tokens being exchanged
    }

    event ExchangeExecuted(address indexed userA, address indexed userB, ExchangeDetails a, ExchangeDetails b);
}
