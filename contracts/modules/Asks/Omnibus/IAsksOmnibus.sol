// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {AsksDataStorage} from "./AsksDataStorage.sol";

/// @title IReserveAuctionOmnibus
/// @author kulkarohan
/// @notice Interface for Reserve Auction Core ERC-20
interface IAsksOmnibus {
    function createAskMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice
    ) external;

    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint96 _expiry,
        uint256 _askPrice,
        address _sellerFundsRecipient,
        address _askCurrency,
        address _buyer,
        uint16 _findersFeeBps,
        uint16 _listingFeeBps,
        address _listingFeeRecipient,
        address _tokenGateToken,
        uint256 _tokenGateMinAmount
    ) external;

    function cancelAsk(address _tokenContract, uint256 _tokenId) external;

    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency
    ) external;

    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency,
        address _finder
    ) external payable;
}
