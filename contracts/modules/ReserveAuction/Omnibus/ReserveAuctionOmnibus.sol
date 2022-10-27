// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

import {IReserveAuctionOmnibus} from "./IReserveAuctionOmnibus.sol";
import {ReserveAuctionDataStorage, FEATURE_MASK_LISTING_FEE, FEATURE_MASK_FINDERS_FEE, FEATURE_MASK_ERC20_CURRENCY, FEATURE_MASK_TOKEN_GATE, FEATURE_MASK_START_TIME, FEATURE_MASK_RECIPIENT_OR_EXPIRY, FEATURE_MASK_BUFFER_AND_INCREMENT} from "./ReserveAuctionDataStorage.sol";

/// @title Reserve Auction Omnibus
/// @author jgeary
/// @notice Omnibus module for multi-featured reserve auctions for ERC-721 tokens
contract ReserveAuctionOmnibus is
    IReserveAuctionOmnibus,
    ReentrancyGuard,
    IncomingTransferSupportV1,
    FeePayoutSupportV1,
    ModuleNamingSupportV1,
    ReserveAuctionDataStorage
{
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint16 constant DEFAULT_TIME_BUFFER = 15 minutes;
    uint16 constant MINIMUM_TIME_BUFFER = 1 minutes;
    uint16 constant MAXIMUM_TIME_BUFFER = 1 hours;

    /// @notice The minimum percentage difference between two bids
    uint8 constant DEFAULT_MIN_BID_INCREMENT_PERCENTAGE = 10;
    uint8 constant MAXIMUM_MIN_BID_INCREMENT_PERCENTAGE = 50;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice Emitted when an auction is created
    /// @param tokenContract The ERC-721 token address of the created auction
    /// @param tokenId The ERC-721 token id of the created auction
    /// @param auction The metadata of the created auction
    event AuctionCreated(address indexed tokenContract, uint256 indexed tokenId, FullAuction auction);

    /// @notice Emitted when a reserve price is updated
    /// @param tokenContract The ERC-721 token address of the updated auction
    /// @param tokenId The ERC-721 token id of the updated auction
    /// @param auction The metadata of the updated auction
    event AuctionReservePriceUpdated(address indexed tokenContract, uint256 indexed tokenId, FullAuction auction);

    /// @notice Emitted when an auction is canceled
    /// @param tokenContract The ERC-721 token address of the canceled auction
    /// @param tokenId The ERC-721 token id of the canceled auction
    /// @param auction The metadata of the canceled auction
    event AuctionCanceled(address indexed tokenContract, uint256 indexed tokenId, FullAuction auction);

    /// @notice Emitted when a bid is placed
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token id of the auction
    /// @param firstBid If the bid started the auction
    /// @param extended If the bid extended the auction
    /// @param auction The metadata of the auction
    event AuctionBid(address indexed tokenContract, uint256 indexed tokenId, bool firstBid, bool extended, FullAuction auction);

    /// @notice Emitted when an auction has ended
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token id of the auction
    /// @param auction The metadata of the settled auction
    event AuctionEnded(address indexed tokenContract, uint256 indexed tokenId, FullAuction auction);

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        IncomingTransferSupportV1(_erc20TransferHelper)
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Reserve Auction Omnibus: ERC20 / Listing Fee / Token Gate / Start Time / Expiry")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IReserveAuctionOmnibus).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    /// @notice Creates a simple ETH auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _reservePrice The ETH price to start bidding
    /// @param _duration The duration of the auction in seconds
    function createAuctionMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice,
        uint64 _duration
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        if (msg.sender != tokenOwner && !IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender)) revert NOT_TOKEN_OWNER_OR_OPERATOR();

        if (_duration <= DEFAULT_TIME_BUFFER) revert DURATION_LTE_TIME_BUFFER();

        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Clear features (if re-used from another auction on the same token)
        auction.features = 0;

        // Store the auction metadata
        auction.seller = tokenOwner;
        auction.reservePrice = _reservePrice;
        auction.duration = _duration;

        emit AuctionCreated(_tokenContract, _tokenId, _getFullAuction(_tokenContract, _tokenId));
    }

    /// @notice Creates an auction for a given NFT
    /// @param auctionData The CreateAuctionParameters struct containing the auction parameters
    function createAuction(IReserveAuctionOmnibus.CreateAuctionParameters calldata auctionData) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(auctionData.tokenContract).ownerOf(auctionData.tokenId);

        // Ensure the caller is the owner or an approved operator
        if (msg.sender != tokenOwner && !IERC721(auctionData.tokenContract).isApprovedForAll(tokenOwner, msg.sender))
            revert NOT_TOKEN_OWNER_OR_OPERATOR();

        if (auctionData.timeBuffer > 0) {
            if (auctionData.duration <= auctionData.timeBuffer) revert DURATION_LTE_TIME_BUFFER();
        } else {
            if (auctionData.duration <= DEFAULT_TIME_BUFFER) revert DURATION_LTE_TIME_BUFFER();
        }

        StoredAuction storage auction = auctionForNFT[auctionData.tokenContract][auctionData.tokenId];

        // Clear features (if re-used from another auction on the same token)
        auction.features = 0;

        if (auctionData.expiry > 0 || (auctionData.fundsRecipient != address(0) && auctionData.fundsRecipient != tokenOwner)) {
            if (auctionData.expiry != 0 && auctionData.expiry <= block.timestamp) revert INVALID_EXPIRY();
            _setExpiryAndFundsRecipient(auction, auctionData.expiry, auctionData.fundsRecipient);
        }

        if (
            (auctionData.listingFeeBps > 0 && auctionData.listingFeeRecipient == address(0)) ||
            (auctionData.listingFeeBps == 0 && auctionData.listingFeeRecipient != address(0))
        ) revert INVALID_LISTING_FEE();
        if (auctionData.listingFeeBps + auctionData.findersFeeBps > 10000) revert INVALID_FEES();

        if (auctionData.listingFeeBps > 0 && auctionData.listingFeeRecipient != address(0)) {
            _setListingFee(auction, auctionData.listingFeeBps, auctionData.listingFeeRecipient);
        }

        if (auctionData.findersFeeBps > 0) {
            _setFindersFee(auction, auctionData.findersFeeBps, address(0));
        }

        if (
            (auctionData.tokenGateMinAmount > 0 && auctionData.tokenGateToken == address(0)) ||
            (auctionData.tokenGateMinAmount == 0 && auctionData.tokenGateToken != address(0))
        ) revert INVALID_TOKEN_GATE();

        if (auctionData.tokenGateToken != address(0)) {
            _setTokenGate(auction, auctionData.tokenGateToken, auctionData.tokenGateMinAmount);
        }

        if (auctionData.startTime > 0) {
            if (auctionData.startTime <= block.timestamp || (auctionData.expiry > 0 && auctionData.expiry <= auctionData.startTime))
                revert INVALID_START_TIME();
            _setStartTime(auction, auctionData.startTime);
        }

        if (auctionData.bidCurrency != address(0)) {
            _setERC20Currency(auction, auctionData.bidCurrency);
        }

        if (auctionData.timeBuffer > 0 || auctionData.percentIncrement > 0) {
            if (auctionData.timeBuffer > 0 && (auctionData.timeBuffer < MINIMUM_TIME_BUFFER || auctionData.timeBuffer > MAXIMUM_TIME_BUFFER))
                revert INVALID_TIME_BUFFER();
            if (auctionData.percentIncrement > 0 && auctionData.percentIncrement > MAXIMUM_MIN_BID_INCREMENT_PERCENTAGE)
                revert INVALID_PERCENT_INCREMENT();
            _setBufferAndIncrement(auction, auctionData.timeBuffer, auctionData.percentIncrement);
        }

        // Store the auction metadata
        auction.seller = tokenOwner;
        auction.reservePrice = auctionData.reservePrice;
        auction.duration = auctionData.duration;

        FullAuction memory fullAuction = _getFullAuction(auctionData.tokenContract, auctionData.tokenId);
        emit AuctionCreated(auctionData.tokenContract, auctionData.tokenId, fullAuction);
    }

    /// @notice Updates the reserve price for a given auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _reservePrice The new reserve price
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external nonReentrant {
        // Get the auction for the specified token
        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        if (auction.seller == address(0)) {
            revert AUCTION_DOES_NOT_EXIST();
        }

        if (ongoingAuctionForNFT[_tokenContract][_tokenId].firstBidTime > 0) {
            revert AUCTION_STARTED();
        }

        // Ensure the caller is the seller
        if (msg.sender != auction.seller && !IERC721(_tokenContract).isApprovedForAll(auction.seller, msg.sender)) {
            revert NOT_TOKEN_OWNER_OR_OPERATOR();
        }

        // Update the reserve price
        auction.reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_tokenContract, _tokenId, _getFullAuction(_tokenContract, _tokenId));
    }

    /// @notice Cancels the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the auction for the specified token
        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Ensure the auction has not started
        if (ongoingAuctionForNFT[_tokenContract][_tokenId].firstBidTime > 0) {
            revert AUCTION_STARTED();
        }

        // If token is still owned by seller, only seller or operator can cancel (otherwise public)
        if (
            IERC721(_tokenContract).ownerOf(_tokenId) == auction.seller &&
            msg.sender != auction.seller &&
            !IERC721(_tokenContract).isApprovedForAll(auction.seller, msg.sender)
        ) {
            revert NOT_TOKEN_OWNER_OR_OPERATOR();
        }

        emit AuctionCanceled(_tokenContract, _tokenId, _getFullAuction(_tokenContract, _tokenId));

        // Remove the auction from storage
        delete auctionForNFT[_tokenContract][_tokenId];
    }

    /// @notice Places a bid on the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _amount The amount to bid
    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        // Get the auction for the specified token
        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = auction.seller;

        // Ensure the auction exists
        if (seller == address(0)) revert AUCTION_DOES_NOT_EXIST();

        // Cache features
        uint32 features = auction.features;

        if (_hasFeature(features, FEATURE_MASK_START_TIME)) {
            uint256 startTime = _getStartTime(auction);
            if (block.timestamp < startTime) revert AUCTION_NOT_STARTED();
        }

        if (_hasFeature(auction.features, FEATURE_MASK_TOKEN_GATE)) {
            (address tokenGateToken, uint256 tokenGateMinAmount) = _getTokenGate(auction);
            if (IERC20(tokenGateToken).balanceOf(msg.sender) < tokenGateMinAmount) revert TOKEN_GATE_INSUFFICIENT_BALANCE();
        }

        // Used to emit whether the bid started the auction
        bool firstBid;

        OngoingAuction memory ongoingAuction = ongoingAuctionForNFT[_tokenContract][_tokenId];

        address currency = _getERC20CurrencyWithFallback(auction);

        // If this is the first bid, start the auction
        if (ongoingAuction.firstBidTime == 0) {
            // Ensure the bid meets the reserve price
            if (_amount < auction.reservePrice) revert RESERVE_PRICE_NOT_MET();

            if (_hasFeature(auction.features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
                (uint96 expiry, ) = _getExpiryAndFundsRecipient(auction);
                if (expiry > 0 && expiry < block.timestamp) revert AUCTION_EXPIRED();
            }

            // Store the amount as the highest bid
            ongoingAuction = OngoingAuction({highestBid: _amount, highestBidder: msg.sender, firstBidTime: uint96(block.timestamp)});

            // Mark this bid as the first
            firstBid = true;

            // Transfer the NFT from the seller into escrow for the duration of the auction
            // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
            erc721TransferHelper.transferFrom(_tokenContract, seller, address(this), _tokenId);

            // Else this is a subsequent bid, so refund the previous bidder
        } else {
            // Ensure the auction has not ended
            if (block.timestamp >= (ongoingAuction.firstBidTime + auction.duration)) revert AUCTION_OVER();

            // Cache the highest bid
            uint256 highestBid = ongoingAuction.highestBid;

            // Used to store the minimum bid required to outbid the highest bidder
            uint256 minValidBid;

            uint8 percentIncrement;
            if (_hasFeature(features, FEATURE_MASK_BUFFER_AND_INCREMENT)) {
                (, percentIncrement) = _getBufferAndIncrement(auction);
            }
            if (percentIncrement == 0) percentIncrement = DEFAULT_MIN_BID_INCREMENT_PERCENTAGE;

            // Calculate the minimum bid required
            // TODO: audit overflow potential now that prices are uint256
            unchecked {
                minValidBid = highestBid + ((highestBid * percentIncrement) / 100);
            }

            // Ensure the incoming bid meets the minimum
            if (_amount < minValidBid) revert MINIMUM_BID_NOT_MET();

            // Refund the previous bidder
            _handleOutgoingTransfer(ongoingAuction.highestBidder, highestBid, currency, 50000);

            ongoingAuction.highestBid = _amount;
            ongoingAuction.highestBidder = msg.sender;
        }

        if (_hasFeature(auction.features, FEATURE_MASK_FINDERS_FEE)) {
            (uint16 findersFeeBps, ) = _getFindersFee(auction);
            _setFindersFee(auction, findersFeeBps, _finder);
        }

        // Retrieve the bid from the bidder
        // If ETH, this reverts if the bidder did not attach enough
        // If ERC-20, this reverts if the bidder did not approve the ERC20TransferHelper or does not own the specified amount
        _handleIncomingTransfer(_amount, currency);

        // Used to emit whether the bid extended the auction
        bool extended;

        // Used to store the auction time remaining
        uint256 timeRemaining;

        // Get the auction time remaining
        // Cannot underflow as `firstBidTime + duration` is ensured to be greater than `block.timestamp`
        unchecked {
            timeRemaining = ongoingAuction.firstBidTime + auction.duration - block.timestamp;
        }

        uint16 timeBuffer;
        if (_hasFeature(features, FEATURE_MASK_BUFFER_AND_INCREMENT)) {
            (timeBuffer, ) = _getBufferAndIncrement(auction);
        }
        if (timeBuffer == 0) timeBuffer = DEFAULT_TIME_BUFFER;

        // If the bid is placed within 15 minutes of the auction end, extend the auction
        if (timeRemaining < timeBuffer) {
            // Add (15 minutes - remaining time) to the duration so that 15 minutes remain
            // Cannot underflow as `timeRemaining` is ensured to be less than `TIME_BUFFER`
            unchecked {
                auction.duration += uint64(timeBuffer - timeRemaining);
            }

            // Mark the bid as one that extended the auction
            extended = true;
        }

        ongoingAuctionForNFT[_tokenContract][_tokenId] = ongoingAuction;
        FullAuction memory fullAuction = _getFullAuction(_tokenContract, _tokenId);
        emit AuctionBid(_tokenContract, _tokenId, firstBid, extended, fullAuction);
    }

    function _handleListingAndFindersFees(
        uint256 _remainingProfit,
        StoredAuction storage auction,
        address currency
    ) internal returns (uint256 remainingProfit) {
        remainingProfit = _remainingProfit;
        uint256 listingFee;
        address listingFeeRecipient;
        uint256 findersFee;
        address finder;

        if (_hasFeature(auction.features, FEATURE_MASK_LISTING_FEE)) {
            uint16 listingFeeBps;
            (listingFeeBps, listingFeeRecipient) = _getListingFee(auction);
            listingFee = (remainingProfit * listingFeeBps) / 10000;
        }

        if (_hasFeature(auction.features, FEATURE_MASK_FINDERS_FEE)) {
            uint16 findersFeeBps;
            (findersFeeBps, finder) = _getFindersFee(auction);
            if (finder != address(0)) {
                findersFee = (remainingProfit * findersFeeBps) / 10000;
            }
        }

        if (listingFee > 0) {
            _handleOutgoingTransfer(listingFeeRecipient, listingFee, currency, 50000);
            remainingProfit -= listingFee;
        }

        if (findersFee > 0) {
            _handleOutgoingTransfer(finder, findersFee, currency, 50000);
            remainingProfit -= findersFee;
        }
    }

    function _handleSellerPayout(
        uint256 profit,
        StoredAuction storage auction,
        address currency
    ) internal {
        address fundsRecipient = auction.seller;

        if (_hasFeature(auction.features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
            (, address _fundsRecipient) = _getExpiryAndFundsRecipient(auction);
            if (_fundsRecipient != address(0)) {
                fundsRecipient = _fundsRecipient;
            }
        }

        // Transfer the remaining profit to the funds recipient
        _handleOutgoingTransfer(fundsRecipient, profit, currency, 50000);
    }

    /// @notice Ends the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function settleAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the auction for the specified token
        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        OngoingAuction memory ongoingAuction = ongoingAuctionForNFT[_tokenContract][_tokenId];

        // Cache the time of the first bid
        uint256 firstBidTime = ongoingAuction.firstBidTime;

        // Ensure the auction had started
        if (firstBidTime == 0) revert AUCTION_NOT_STARTED();

        // Ensure the auction has ended
        if (block.timestamp < (firstBidTime + auction.duration)) revert AUCTION_NOT_OVER();

        // Cache the auction currency
        address currency = _getERC20CurrencyWithFallback(auction);

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, ongoingAuction.highestBid, currency, 300000);

        // Payout the module fee, if configured by the owner
        remainingProfit = _handleProtocolFeePayout(remainingProfit, currency);

        remainingProfit = _handleListingAndFindersFees(remainingProfit, auction, currency);

        _handleSellerPayout(remainingProfit, auction, currency);

        // Transfer the NFT to the winning bidder
        IERC721(_tokenContract).transferFrom(address(this), ongoingAuction.highestBidder, _tokenId);

        emit AuctionEnded(_tokenContract, _tokenId, _getFullAuction(_tokenContract, _tokenId));

        // Remove the auction from storage
        delete auctionForNFT[_tokenContract][_tokenId];
        // Remove the auction ongoing state from storage
        delete ongoingAuctionForNFT[_tokenContract][_tokenId];
    }

    function getFullAuction(address _tokenContract, uint256 _tokenId) external view returns (FullAuction memory) {
        return _getFullAuction(_tokenContract, _tokenId);
    }
}
