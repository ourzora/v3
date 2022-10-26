// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReserveAuctionDataStorage} from "./ReserveAuctionDataStorage.sol";

/// @title IReserveAuctionOmnibus
/// @author kulkarohan
/// @notice Interface for Reserve Auction Core ERC-20
interface IReserveAuctionOmnibus {
    error NOT_TOKEN_OWNER_OR_OPERATOR();

    error DURATION_LTE_TIME_BUFFER();

    error INVALID_EXPIRY();

    error INVALID_LISTING_FEE();

    error INVALID_FEES();

    error INVALID_TOKEN_GATE();

    error INVALID_START_TIME();

    error INVALID_TIME_BUFFER();

    error INVALID_PERCENT_INCREMENT();

    error RESERVE_PRICE_NOT_MET();

    error AUCTION_STARTED();

    error AUCTION_OVER();

    error AUCTION_NOT_STARTED();

    error AUCTION_NOT_OVER();

    error AUCTION_DOES_NOT_EXIST();

    error AUCTION_EXPIRED();

    error TOKEN_GATE_INSUFFICIENT_BALANCE();

    error MINIMUM_BID_NOT_MET();

    struct CreateAuctionParameters {
        uint256 tokenId;
        uint256 reservePrice;
        uint256 expiry;
        uint256 startTime;
        uint256 tokenGateMinAmount;
        address tokenContract;
        uint64 duration;
        uint16 findersFeeBps;
        uint16 timeBuffer;
        address fundsRecipient;
        uint16 listingFeeBps;
        uint8 percentIncrement;
        address listingFeeRecipient;
        address tokenGateToken;
        address bidCurrency;
    }

    function createAuctionMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice,
        uint64 _duration
    ) external;

    function createAuction(CreateAuctionParameters calldata auctionData) external;

    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external;

    function cancelAuction(address _tokenContract, uint256 _tokenId) external;

    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address finder
    ) external payable;

    function settleAuction(address _tokenContract, uint256 _tokenId) external;
}
