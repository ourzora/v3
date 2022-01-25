// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title RoyaltyEngine
/// @notice FOR TEST PURPOSES ONLY.
contract RoyaltyEngine {
    address public recipient;

    constructor(address _royaltyRecipient) {
        recipient = _royaltyRecipient;
    }

    event RoyaltyView(address tokenAddress, uint256 tokenId, uint256 value);

    function getRoyalty(
        address tokenAddress,
        uint256 tokenId,
        uint256 value
    ) public returns (address payable[] memory, uint256[] memory) {
        address payable[] memory recipients = new address payable[](1);
        recipients[0] = payable(address(recipient));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.05 ether; // Hardcoded royalty amount

        emit RoyaltyView(tokenAddress, tokenId, value);

        return (recipients, amounts);
    }
}
