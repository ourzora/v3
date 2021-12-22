// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title Reserve Auction V1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to list and bid on ERC-721 tokens with timed reserve auctions
contract ReserveAuctionV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
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

    /// @notice A mapping of NFTs to their respective auction ID
    /// @dev NFT address => NFT ID => auction ID
    mapping(address => mapping(uint256 => Auction)) public auctionForNFT;

    struct Auction {
        address seller; // The address that should receive the funds once the NFT is sold.
        address auctionCurrency; // The address of the ERC-20 currency (0x0 for ETH) to run the auction with.
        address payable sellerFundsRecipient; // The address of the recipient of the auction's highest bid
        address payable bidder; // The address of the current highest bid
        address payable finder; // The address of the current bid's finder
        uint256 amount; // The current highest bid amount
        uint256 duration; // The length of time to run the auction for, after the first bid was made
        uint256 startTime; // The time of the auction start
        uint256 firstBidTime; // The time of the first bid
        uint256 reservePrice; // The minimum price of the first bid
        uint256 findersFeePercentage; // The sale percentage to send to the winning bid finder
    }

    event AuctionCreated(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    event AuctionReservePriceUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed reservePrice, Auction auction);

    event AuctionBid(
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 indexed amount,
        address bidder,
        bool firstBid,
        bool extended,
        Auction auction
    );

    event AuctionDurationExtended(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed duration, Auction auction);

    event AuctionEnded(address indexed tokenContract, uint256 indexed tokenId, address indexed winner, address finder, Auction auction);

    event AuctionCanceled(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

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

    /// @notice Creates an auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token being auctioned for sale
    /// @param _duration The amount of time the auction should run for after the initial bid is placed
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @param _startTime The time to start the auction
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _sellerFundsRecipient,
        uint256 _findersFeePercentage,
        address _auctionCurrency,
        uint256 _startTime
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAuction must be token owner or approved operator"
        );
        require(
            (IERC721(_tokenContract).getApproved(_tokenId) == address(erc721TransferHelper)) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createAuction must approve ZORA ERC-721 Transfer Helper from _tokenContract"
        );

        if (auctionForNFT[_tokenContract][_tokenId].seller != ADDRESS_ZERO) {
            _cancelAuction(_tokenContract, _tokenId);
        }
        require(_findersFeePercentage <= 100, "createAuction _findersFeePercentage must be less than or equal to 100");
        require(_sellerFundsRecipient != ADDRESS_ZERO, "createAuction _sellerFundsRecipient cannot be 0 address");
        require((_startTime == 0) || (_startTime > block.timestamp), "createAuction _startTime must be 0 or a future block");

        if (_startTime == 0) {
            _startTime = block.timestamp;
        }

        auctionForNFT[_tokenContract][_tokenId] = Auction({
            seller: tokenOwner,
            auctionCurrency: _auctionCurrency,
            sellerFundsRecipient: _sellerFundsRecipient,
            bidder: payable(ADDRESS_ZERO),
            finder: payable(ADDRESS_ZERO),
            amount: 0,
            duration: _duration,
            startTime: _startTime,
            firstBidTime: 0,
            reservePrice: _reservePrice,
            findersFeePercentage: _findersFeePercentage
        });

        emit AuctionCreated(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);
    }

    /// @notice Update the reserve price for a given auction
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    /// @param _reservePrice The new reserve price for the auction
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(msg.sender == auction.seller, "setAuctionReservePrice must be token owner or operator");
        require(auction.firstBidTime == 0, "setAuctionReservePrice auction has already started");

        auction.reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_tokenContract, _tokenId, _reservePrice, auction);
    }

    /// @notice Places a bid on the auction, holding the bids in escrow and refunding any previous bids
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    /// @param _amount The bid amount to be transferred
    /// @param _finder The address of the referrer for this bid
    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];
        address payable lastBidder = auction.bidder;

        require(auction.seller != ADDRESS_ZERO, "createBid auction doesn't exist");
        require(block.timestamp >= auction.startTime, "createBid auction hasn't started");
        require(auction.firstBidTime == 0 || block.timestamp < (auction.firstBidTime + auction.duration), "createBid auction expired");
        require(_amount >= auction.reservePrice, "createBid must send at least reservePrice");
        require(
            _amount >= (auction.amount + ((auction.amount * minBidIncrementPercentage) / 100)),
            "createBid must send more than the last bid by minBidIncrementPercentage amount"
        );

        // For Zora V1 Protocol, ensure that the bid is valid for the current bidShare configuration
        if (_tokenContract == zoraV1Media) {
            require(IZoraV1Market(zoraV1Market).isValidBid(_tokenId, _amount), "createBid bid invalid for share splitting");
        }

        // If this is the first valid bid, we should set the starting time now and take the NFT into escrow
        // If it's not, then we should refund the last bidder
        if (auction.firstBidTime == 0) {
            auction.firstBidTime = block.timestamp;
            erc721TransferHelper.transferFrom(_tokenContract, auction.seller, address(this), _tokenId);
        } else if (lastBidder != ADDRESS_ZERO) {
            _handleOutgoingTransfer(lastBidder, auction.amount, auction.auctionCurrency, USE_ALL_GAS_FLAG);
        }

        _handleIncomingTransfer(_amount, auction.auctionCurrency);

        auction.amount = _amount;
        auction.bidder = payable(msg.sender);
        auction.finder = payable(_finder);

        bool extended;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if ((auction.firstBidTime + auction.duration - block.timestamp) < timeBuffer) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionId].firstBidTime.add(auctions[auctionId].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionId].duration.add(timeToAdd);
            uint256 oldDuration = auction.duration;
            auction.duration = oldDuration + (timeBuffer - (auction.firstBidTime + oldDuration - block.timestamp));
            extended = true;
        }

        emit AuctionBid(
            _tokenContract,
            _tokenId,
            _amount,
            msg.sender,
            lastBidder == ADDRESS_ZERO, // firstBid boolean
            extended,
            auction
        );

        if (extended) {
            emit AuctionDurationExtended(_tokenContract, _tokenId, auction.duration, auction);
        }
    }

    /// @notice End an auction, paying out respective parties and transferring the token to the winning bidder
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function settleAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != ADDRESS_ZERO, "settleAuction auction doesn't exist");
        require(auction.firstBidTime != 0, "settleAuction auction hasn't begun");
        require(block.timestamp >= (auction.firstBidTime + auction.duration), "settleAuction auction hasn't completed");

        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, auction.amount, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        if (auction.finder != ADDRESS_ZERO) {
            uint256 finderFee = (remainingProfit * auction.findersFeePercentage) / 100;
            _handleOutgoingTransfer(auction.finder, finderFee, auction.auctionCurrency, USE_ALL_GAS_FLAG);

            remainingProfit -= finderFee;
        }

        _handleOutgoingTransfer(auction.sellerFundsRecipient, remainingProfit, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to winning bidder
        IERC721(_tokenContract).transferFrom(address(this), auction.bidder, _tokenId);

        UniversalExchangeEventV1.ExchangeDetails memory userAExchangeDetails = UniversalExchangeEventV1.ExchangeDetails({
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            amount: 1
        });

        UniversalExchangeEventV1.ExchangeDetails memory userBExchangeDetails = UniversalExchangeEventV1.ExchangeDetails({
            tokenContract: auction.auctionCurrency,
            tokenId: 0,
            amount: auction.amount
        });

        emit ExchangeExecuted(auction.seller, auction.bidder, userAExchangeDetails, userBExchangeDetails);
        emit AuctionEnded(_tokenContract, _tokenId, auction.bidder, auction.finder, auction);

        delete auctionForNFT[_tokenContract][_tokenId];
    }

    /// @notice Cancel an auction
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != ADDRESS_ZERO, "cancelAuction auction doesn't exist");
        require(auction.firstBidTime == 0, "cancelAuction auction already started");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        require(
            (msg.sender == tokenOwner) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) ||
                (msg.sender == IERC721(_tokenContract).getApproved(_tokenId)),
            "cancelAuction must be auction creator or invalid auction"
        );

        _cancelAuction(_tokenContract, _tokenId);
    }

    /// @notice Removes an auction
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function _cancelAuction(address _tokenContract, uint256 _tokenId) private {
        emit AuctionCanceled(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);

        delete auctionForNFT[_tokenContract][_tokenId];
    }
}
