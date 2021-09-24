// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {LibReserveAuctionV1} from "./LibReserveAuctionV1.sol";

contract ReserveAuctionV1 is ReentrancyGuard {
    using LibReserveAuctionV1 for LibReserveAuctionV1.ReserveAuctionStorage;

    LibReserveAuctionV1.ReserveAuctionStorage reserveAuctionStorage;

    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _zoraV1ProtocolMedia,
        address _wethAddress
    ) {
        reserveAuctionStorage.init(_erc20TransferHelper, _erc721TransferHelper, _zoraV1ProtocolMedia, _wethAddress);
    }

    function auctions(uint256 _auctionId) external view returns (LibReserveAuctionV1.Auction memory) {
        return reserveAuctionStorage.auctions[_auctionId];
    }

    function nftToAuctionId(address _tokenAddress, uint256 _tokenId) external view returns (uint256) {
        return reserveAuctionStorage.nftToAuctionId[_tokenAddress][_tokenId];
    }

    function createAuction(
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _host,
        address payable _fundsRecipient,
        uint8 _listingFeePercentage,
        uint8 _findersFeePercentage,
        address _auctionCurrency
    ) public nonReentrant returns (uint256) {
        return
            reserveAuctionStorage.createAuction(
                _tokenId,
                _tokenContract,
                _duration,
                _reservePrice,
                _host,
                _fundsRecipient,
                _listingFeePercentage,
                _findersFeePercentage,
                _auctionCurrency
            );
    }

    function setAuctionReservePrice(uint256 _auctionId, uint256 _reservePrice) external {
        reserveAuctionStorage.setAuctionReservePrice(_auctionId, _reservePrice);
    }

    function createBid(
        uint256 _auctionId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        reserveAuctionStorage.createBid(_auctionId, _amount, _finder);
    }

    function settleAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.settleAuction(_auctionId);
    }

    function cancelAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.cancelAuction(_auctionId);
    }
}
