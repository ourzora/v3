// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title Reserve Auction V1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to list and bid on ERC-721 tokens with timed reserve auctions
contract ReserveAuctionV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeMath for uint8;

    address private constant ADDRESS_ZERO = address(0);
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA V1 NFT Protocol Media Contract address
    address public immutable zoraV1Media;
    /// @notice The ZORA V1 NFT Protocol Market Contract address
    address public immutable zoraV1Market;
    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The minimum percentage difference between the last bid amount and the current bid.
    uint8 constant minBidIncrementPercentage = 10; // 10%
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint256 constant timeBuffer = 15 * 60; // 15 minutes

    /// @notice A mapping of IDs to their respective auction
    mapping(uint256 => Auction) public auctions;
    /// @notice A mapping of IDs to their respective auction fees
    mapping(uint256 => Fees) public fees;

    /// @notice A mapping of NFTs to their respective auction ID
    /// @dev NFT address => NFT ID => auction ID
    mapping(address => mapping(uint256 => uint256)) public auctionForNFT;

    /// @notice The number of total auctions
    Counters.Counter public auctionCounter;

    struct Auction {
        address tokenContract; // Address for the ERC721 contract
        address seller; // The address that should receive the funds once the NFT is sold.
        address auctionCurrency; // The address of the ERC-20 currency (0x0 for ETH) to run the auction with.
        address payable fundsRecipient; // The address of the recipient of the auction's highest bid
        address payable bidder; // The address of the current highest bid
        uint256 tokenId; // ID for the ERC721 token
        uint256 amount; // The current highest bid amount
        uint256 duration; // The length of time to run the auction for, after the first bid was made
        uint256 startTime; // The time of the auction start
        uint256 firstBidTime; // The time of the first bid
        uint256 reservePrice; // The minimum price of the first bid
    }

    struct Fees {
        address payable listingFeeRecipient; // The address of the auction's listingFeeRecipient.
        address payable finder; // The address of the current bid's finder
        uint8 listingFeePercentage; // The sale percentage to send to the listingFeeRecipient
        uint8 findersFeePercentage; // The sale percentage to send to the winning bid finder
    }

    event AuctionCreated(uint256 indexed id, Auction auction, Fees fees);

    event AuctionReservePriceUpdated(uint256 indexed id, uint256 indexed reservePrice, Auction auction);

    event AuctionBid(uint256 indexed id, address indexed bidder, uint256 indexed amount, bool firstBid, bool extended, Auction auction);

    event AuctionDurationExtended(uint256 indexed id, uint256 indexed duration, Auction auction);

    event AuctionEnded(uint256 indexed id, address indexed winner, address indexed finder, Auction auction, Fees fees);

    event AuctionCanceled(uint256 indexed id, Auction auction, Fees fees);

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _zoraV1Media The ZORA NFT Protocol Media Contract address
    /// @param _zoraV1Market The ZORA NFT Protocol Market Contract address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _wethAddress WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _zoraV1Media,
        address _zoraV1Market,
        address _royaltyEngine,
        address _wethAddress
    ) IncomingTransferSupportV1(_erc20TransferHelper) RoyaltyPayoutSupportV1(_royaltyEngine, _wethAddress) {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
        zoraV1Media = _zoraV1Media;
        zoraV1Market = _zoraV1Market;
    }

    /// @notice Create an auction.
    /// @param _tokenId The ID of the ERC-721 token being listed for sale
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _duration The amount of time the auction should run for after the initial bid is placed
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _listingFeeRecipient The listingFeeRecipient of the sale, who can receive _listingFeePercentage of the sale price
    /// @param _fundsRecipient The address to send funds to once the token is sold
    /// @param _listingFeePercentage The percentage of the sale amount to be sent to the listingFeeRecipient
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @param _startTime The time to start the auction
    /// @return The ID of the created auction
    function createAuction(
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _listingFeeRecipient,
        address payable _fundsRecipient,
        uint8 _listingFeePercentage,
        uint8 _findersFeePercentage,
        address _auctionCurrency,
        uint256 _startTime
    ) public nonReentrant returns (uint256) {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) ||
                (msg.sender == IERC721(_tokenContract).getApproved(_tokenId)),
            "createAuction must be token owner or approved operator"
        );
        if (auctionForNFT[_tokenContract][_tokenId] != 0) {
            _cancelAuction(auctionForNFT[_tokenContract][_tokenId]);
        }
        require((_listingFeePercentage + _findersFeePercentage) < 100, "createAuction _listingFeePercentage plus _findersFeePercentage must be less than 100");
        require(_fundsRecipient != ADDRESS_ZERO, "createAuction _fundsRecipient cannot be 0 address");
        require((_startTime == 0) || (_startTime > block.timestamp), "createAuction _startTime must be 0 or a future block time");

        if (_startTime == 0) {
            _startTime = block.timestamp;
        }

        auctionCounter.increment();
        uint256 auctionId = auctionCounter.current();

        auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            amount: 0,
            duration: _duration,
            startTime: _startTime,
            firstBidTime: 0,
            reservePrice: _reservePrice,
            seller: msg.sender,
            bidder: payable(ADDRESS_ZERO),
            fundsRecipient: _fundsRecipient,
            auctionCurrency: _auctionCurrency
        });

        fees[auctionId] = Fees({
            listingFeeRecipient: _listingFeeRecipient,
            finder: payable(ADDRESS_ZERO),
            listingFeePercentage: _listingFeePercentage,
            findersFeePercentage: _findersFeePercentage
        });

        auctionForNFT[_tokenContract][_tokenId] = auctionId;

        emit AuctionCreated(auctionId, auctions[auctionId], fees[auctionId]);

        return auctionId;
    }

    /// @notice Update the reserve price for a given auction
    /// @param _auctionId The ID for the auction
    /// @param _reservePrice The new reserve price for the auction
    function setAuctionReservePrice(uint256 _auctionId, uint256 _reservePrice) external {
        Auction storage auction = auctions[_auctionId];

        require(_auctionId == auctionForNFT[auction.tokenContract][auction.tokenId], "setAuctionReservePrice auction doesn't exist");
        require(msg.sender == auction.seller, "setAuctionReservePrice must be token owner");
        require(auction.firstBidTime == 0, "setAuctionReservePrice auction has already started");

        auction.reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_auctionId, _reservePrice, auction);
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
        Auction storage auction = auctions[_auctionId];
        address payable lastBidder = auction.bidder;

        require(_auctionId == auctionForNFT[auction.tokenContract][auction.tokenId], "createBid auction doesn't exist");
        require(block.timestamp >= auction.startTime, "createBid auction hasn't started");
        require(auction.firstBidTime == 0 || block.timestamp < (auction.firstBidTime + auction.duration), "createBid auction expired");
        require(_amount >= auction.reservePrice, "createBid must send at least reservePrice");
        require(
            _amount >= auction.amount.add(auction.amount.mul(minBidIncrementPercentage).div(100)),
            "createBid must send more than the last bid by minBidIncrementPercentage amount"
        );
        require(_finder != ADDRESS_ZERO, "createBid _finder must not be 0 address");

        // For Zora V1 Protocol, ensure that the bid is valid for the current bidShare configuration
        if (auction.tokenContract == zoraV1Media) {
            require(IZoraV1Market(zoraV1Market).isValidBid(auction.tokenId, _amount), "createBid bid invalid for share splitting");
        }

        // If this is the first valid bid, we should set the starting time now and take the NFT into escrow
        // If it's not, then we should refund the last bidder
        if (auction.firstBidTime == 0) {
            auction.firstBidTime = block.timestamp;

            erc721TransferHelper.transferFrom(auction.tokenContract, auction.seller, address(this), auction.tokenId);
        } else if (lastBidder != ADDRESS_ZERO) {
            _handleOutgoingTransfer(lastBidder, auction.amount, auction.auctionCurrency, USE_ALL_GAS_FLAG);
        }

        _handleIncomingTransfer(_amount, auction.auctionCurrency);

        auction.amount = _amount;
        auction.bidder = payable(msg.sender);
        fees[_auctionId].finder = payable(_finder);

        bool extended;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if (auction.firstBidTime.add(auction.duration).sub(block.timestamp) < timeBuffer) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionId].firstBidTime.add(auctions[auctionId].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionId].duration.add(timeToAdd);
            uint256 oldDuration = auction.duration;
            auction.duration = oldDuration.add(timeBuffer.sub(auction.firstBidTime.add(oldDuration).sub(block.timestamp)));
            extended = true;
        }

        emit AuctionBid(
            _auctionId,
            msg.sender,
            _amount,
            lastBidder == ADDRESS_ZERO, // firstBid boolean
            extended,
            auction
        );

        if (extended) {
            emit AuctionDurationExtended(_auctionId, auction.duration, auction);
        }
    }

    /// @notice End an auction, paying out respective parties and transferring the token to the winning bidder
    /// @param _auctionId The ID of  the auction
    function settleAuction(uint256 _auctionId) external nonReentrant {
        Auction storage auction = auctions[_auctionId];

        require(_auctionId == auctionForNFT[auction.tokenContract][auction.tokenId], "settleAuction auction doesn't exist");
        require(auction.firstBidTime != 0, "settleAuction auction hasn't begun");
        require(block.timestamp >= auction.firstBidTime.add(auction.duration), "settleAuction auction hasn't completed");

        Fees storage auctionFees = fees[_auctionId];

        (uint256 remainingProfit, ) = _handleRoyaltyPayout(auction.tokenContract, auction.tokenId, auction.amount, auction.auctionCurrency, USE_ALL_GAS_FLAG);
        uint256 listingFeeRecipientProfit = remainingProfit.mul(auctionFees.listingFeePercentage).div(100);
        uint256 finderFee = remainingProfit.mul(auctionFees.findersFeePercentage).div(100);

        _handleOutgoingTransfer(auctionFees.listingFeeRecipient, listingFeeRecipientProfit, auction.auctionCurrency, USE_ALL_GAS_FLAG);
        _handleOutgoingTransfer(auctionFees.finder, finderFee, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        remainingProfit = remainingProfit.sub(listingFeeRecipientProfit).sub(finderFee);

        _handleOutgoingTransfer(auction.fundsRecipient, remainingProfit, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        UniversalExchangeEventV1.ExchangeDetails memory userAExchangeDetails = UniversalExchangeEventV1.ExchangeDetails({
            tokenContract: auction.tokenContract,
            tokenId: auction.tokenId,
            amount: 1
        });

        UniversalExchangeEventV1.ExchangeDetails memory userBExchangeDetails = UniversalExchangeEventV1.ExchangeDetails({
            tokenContract: auction.auctionCurrency,
            tokenId: 0,
            amount: auction.amount
        });

        emit ExchangeExecuted(auction.seller, auction.bidder, userAExchangeDetails, userBExchangeDetails);
        emit AuctionEnded(_auctionId, auction.bidder, auctionFees.finder, auction, auctionFees);

        delete auctionForNFT[auction.tokenContract][auction.tokenId];
        delete auctions[_auctionId];
        delete fees[_auctionId];
    }

    /// @notice Cancel an auction
    /// @param _auctionId The ID of the auction
    function cancelAuction(uint256 _auctionId) public nonReentrant {
        Auction storage auction = auctions[_auctionId];

        require(_auctionId == auctionForNFT[auction.tokenContract][auction.tokenId], "cancelAuction auction doesn't exist");
        require(auction.firstBidTime == 0, "cancelAuction auction already started");

        address tokenOwner = IERC721(auction.tokenContract).ownerOf(auction.tokenId);
        bool isTokenOwner = tokenOwner == msg.sender;
        bool isOperatorForTokenOwner = IERC721(auction.tokenContract).isApprovedForAll(tokenOwner, msg.sender);
        bool isApprovedForToken = IERC721(auction.tokenContract).getApproved(auction.tokenId) == msg.sender;

        require(
            (msg.sender == auction.seller) || isTokenOwner || isOperatorForTokenOwner || isApprovedForToken,
            "cancelAuction must be auction creator or invalid auction"
        );

        _cancelAuction(_auctionId);
    }

    /// @notice Removes an auction
    /// @param _auctionId The ID of the auction
    function _cancelAuction(uint256 _auctionId) private {
        Auction storage auction = auctions[_auctionId];

        emit AuctionCanceled(_auctionId, auction, fees[_auctionId]);

        delete auctionForNFT[auction.tokenContract][auction.tokenId];
        delete auctions[_auctionId];
        delete fees[_auctionId];
    }
}
