// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {LibReserveAuctionV1} from "./LibReserveAuctionV1.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";

/// @title Reserve Auction V1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to list and bid on ERC-721 tokens with timed reserve auctions
contract ReserveAuctionV1 is ReentrancyGuard, UniversalExchangeEventV1 {
    using LibReserveAuctionV1 for LibReserveAuctionV1.ReserveAuctionStorage;

    LibReserveAuctionV1.ReserveAuctionStorage reserveAuctionStorage;

    event AuctionCreated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address tokenOwner,
        address host,
        address fundsRecipient,
        uint8 listingFeePercentage,
        address auctionCurrency
    );

    event AuctionReservePriceUpdated(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, uint256 reservePrice);

    event AuctionBid(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address sender,
        address finder,
        uint256 value,
        bool firstBid,
        bool extended
    );

    event AuctionDurationExtended(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, uint256 duration);

    event AuctionEnded(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address host,
        address winner,
        address fundsRecipient,
        uint256 amount,
        uint256 finderFee,
        uint256 listingFee,
        address auctionCurrency
    );

    event AuctionCanceled(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, address tokenOwner);

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _zoraV1ProtocolMedia The ZORA NFT Protocol Media Contract address
    /// @param _royaltyRegistry The ZORA Collection Royalty Registry address
    /// @param _wethAddress WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _zoraV1ProtocolMedia,
        address _royaltyRegistry,
        address _wethAddress
    ) {
        reserveAuctionStorage.init(_erc20TransferHelper, _erc721TransferHelper, _zoraV1ProtocolMedia, _royaltyRegistry, _wethAddress);
    }

    /// @notice Returns an auction for a given ID
    /// @param _auctionId the ID of the auction
    /// @return an Auction object
    function auctions(uint256 _auctionId) external view returns (LibReserveAuctionV1.Auction memory) {
        return reserveAuctionStorage.auctions[_auctionId];
    }

    /// @notice Returns an auction ID for a given NFT
    /// @param _tokenAddress The address of the ERC-721 token
    /// @param _tokenId the ID of the ERC-721 token
    function nftToAuctionId(address _tokenAddress, uint256 _tokenId) external view returns (uint256) {
        return reserveAuctionStorage.nftToAuctionId[_tokenAddress][_tokenId];
    }

    /// @notice Create an auction.
    /// @param _tokenId The ID of the ERC-721 token being listed for sale
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _duration The amount of time the auction should run for after the initial bid is placed
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _host The host of the sale, who can receive _listingFeePercentage of the sale price
    /// @param _fundsRecipient The address to send funds to once the token is sold
    /// @param _listingFeePercentage The percentage of the sale amount to be sent to the host
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @return The ID of the created auction
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

    /// @notice Update the reserve price for a given auction
    /// @param _auctionId The ID for the auction
    /// @param _reservePrice The new reserve price for the auction
    function setAuctionReservePrice(uint256 _auctionId, uint256 _reservePrice) external {
        reserveAuctionStorage.setAuctionReservePrice(_auctionId, _reservePrice);
    }

    /// @notice Places a bid on the auction, holding the bids in escrow and refunding any previous bids
    /// @param _auctionId The ID of the auction
    /// @param _amount The bid amount to be transferred
    /// @param _finder The address of the referrer for this bid
    function createBid(
        uint256 _auctionId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        reserveAuctionStorage.createBid(_auctionId, _amount, _finder);
    }

    /// @notice End an auction, paying out respective parties and transferring the token to the winning bidder
    /// @param _auctionId The ID of  the auction
    function settleAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.settleAuction(_auctionId);
    }

    /// @notice Cancel an auction
    /// @param _auctionId The ID of the auction
    function cancelAuction(uint256 _auctionId) external nonReentrant {
        reserveAuctionStorage.cancelAuction(_auctionId);
    }
}
