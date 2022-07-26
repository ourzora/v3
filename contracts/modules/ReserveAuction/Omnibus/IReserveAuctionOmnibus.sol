// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReserveAuctionDataStorage} from "./ReserveAuctionDataStorage.sol";

/// @title IReserveAuctionOmnibus
/// @author kulkarohan
/// @notice Interface for Reserve Auction Core ERC-20
interface IReserveAuctionOmnibus {
    function createAuctionMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice,
        uint64 _duration
    ) external;

    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint64 _duration,
        uint256 _reservePrice,
        address _fundsRecipient,
        uint96 _expiry,
        uint256 _startTime,
        address _bidCurrency,
        uint16 _findersFeeBps,
        ReserveAuctionDataStorage.ListingFee memory _listingFee,
        ReserveAuctionDataStorage.TokenGate memory _tokenGate
    ) external;

    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external;

    function cancelAuction(address _tokenContract, uint256 _tokenId) external;

    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount
    ) external payable;

    function settleAuction(address _tokenContract, uint256 _tokenId) external;
}
