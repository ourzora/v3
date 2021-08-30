// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {LibReserveAuctionV1} from "./LibReserveAuctionV1.sol";

contract ReserveAuctionV1 is ReentrancyGuard {
    using LibReserveAuctionV1 for LibReserveAuctionV1.ReserveAuctionStorage;

    LibReserveAuctionV1.ReserveAuctionStorage reserveAuctionStorage;

    constructor(address _zoraV1ProtocolMedia, address _wethAddress) {
        reserveAuctionStorage.init(_zoraV1ProtocolMedia, _wethAddress);
    }

    function auctions(uint256 _auctionId) external view returns (LibReserveAuctionV1.Auction memory) {
        return reserveAuctionStorage.auctions[_auctionId];
    }

    function createAuction(
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _curator,
        address payable _fundsRecipient,
        uint8 _curatorFeePercentage,
        address _auctionCurrency
    ) public nonReentrant returns (uint256) {
        return
            reserveAuctionStorage.createAuction(
                _tokenId,
                _tokenContract,
                _duration,
                _reservePrice,
                _curator,
                _fundsRecipient,
                _curatorFeePercentage,
                _auctionCurrency
            );
    }

    function setAuctionApproval(uint256 _auctionId, bool _approved) external {
        reserveAuctionStorage.setAuctionApproval(_auctionId, _approved);
    }

    function setAuctionReservePrice(uint256 _auctionId, uint256 _reservePrice) external {
        reserveAuctionStorage.setAuctionReservePrice(_auctionId, _reservePrice);
    }

    function createBid(uint256 _auctionId, uint256 _amount) external payable nonReentrant {
        reserveAuctionStorage.createBid(_auctionId, _amount);
    }

    function endAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.endAuction(_auctionId);
    }

    function cancelAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.cancelAuction(_auctionId);
    }
}
