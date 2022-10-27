// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {AsksDataStorage} from "./AsksDataStorage.sol";

/// @title IReserveAuctionOmnibus
/// @author kulkarohan
/// @notice Interface for Reserve Auction Core ERC-20
interface IAsksOmnibus {
    error NOT_TOKEN_OWNER_OR_OPERATOR();

    error MODULE_NOT_APPROVED();

    error TRANSFER_HELPER_NOT_APPROVED();

    error INVALID_LISTING_FEE();

    error INVALID_FEES();

    error INVALID_TOKEN_GATE();

    error INVALID_EXPIRY();

    error ASK_INACTIVE();

    error ASK_EXPIRED();

    error INCORRECT_CURRENCY_OR_AMOUNT();

    error TOKEN_GATE_INSUFFICIENT_BALANCE();

    error NOT_DESIGNATED_BUYER();

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
