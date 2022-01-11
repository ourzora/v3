// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IFeeTokenURI {
    function tokenURIForFeeSchedule(
        uint256 tokenId,
        address tokenOwner,
        address moduleAddress,
        uint16 feeBps,
        address feeRecipient
    ) external view returns (string memory);
}
