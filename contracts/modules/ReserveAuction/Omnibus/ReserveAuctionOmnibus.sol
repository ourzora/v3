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
import {ReserveAuctionDataStorage, FEATURE_MASK_LISTING_FEE, FEATURE_MASK_FINDERS_FEE, FEATURE_MASK_ERC20_CURRENCY, FEATURE_MASK_TOKEN_GATE, FEATURE_MASK_START_TIME, FEATURE_MASK_RECIPIENT_OR_EXPIRY} from "./ReserveAuctionDataStorage.sol";

/// @title Reserve Auction Omnibus
/// @author jgeary
/// @notice Omnibus module for multi-featured reserve auctions for ERC-721 tokens
contract ReserveAuctionOmnibus is ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1, ReserveAuctionDataStorage {
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint16 constant TIME_BUFFER = 15 minutes;

    /// @notice The minimum percentage difference between two bids
    uint8 constant MIN_BID_INCREMENT_PERCENTAGE = 10;

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
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        require(_duration > TIME_BUFFER, "duration must be greater than minimum time buffer");

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
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _duration The length of time the auction should run after the first bid
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _fundsRecipient The address to send funds to once the auction is complete
    /// @param _expiry The time after which a user can no longer place a first bid
    /// @param _startTime The time that users can begin placing bids
    /// @param _bidCurrency The address of the ERC-20 token, or address(0) for ETH, that users must bid with
    /// @param _findersFeeBps Finder's fee basis points
    /// @param _listingFee Listing fee (basis points and recipient)
    /// @param _tokenGate Token gate (address and min amount)
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint64 _duration,
        uint256 _reservePrice,
        address _fundsRecipient,
        uint256 _expiry,
        uint256 _startTime,
        address _bidCurrency,
        uint16 _findersFeeBps,
        ReserveAuctionDataStorage.ListingFee memory _listingFee,
        ReserveAuctionDataStorage.TokenGate memory _tokenGate
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        require(_duration > TIME_BUFFER, "duration must be greater than minimum time buffer");

        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Clear features (if re-used from another auction on the same token)
        auction.features = 0;

        if (_expiry > 0 || (_fundsRecipient != address(0) && _fundsRecipient != tokenOwner)) {
            require(_expiry == 0 || (_expiry > block.timestamp && _expiry < type(uint96).max), "Expiry must be in the future");
            _setExpiryAndFundsRecipient(auction, uint96(_expiry), _fundsRecipient);
        }

        if (_listingFee.listingFeeBps > 0 && _listingFee.listingFeeRecipient != address(0)) {
            // Ensure the listing fee does not exceed 10,000 basis points
            require(_listingFee.listingFeeBps <= 10000, "INVALID_LISTING_FEE");
            _setListingFee(auction, _listingFee.listingFeeBps, _listingFee.listingFeeRecipient);
        }

        if (_findersFeeBps > 0) {
            require(_findersFeeBps <= 10000, "createAsk finders fee bps must be less than or equal to 10000");
            require(_findersFeeBps + _listingFee.listingFeeBps <= 10000, "listingFee + findersFee must be less than or equal to 10000");
            _setFindersFee(auction, _findersFeeBps, address(0));
        }

        if (_tokenGate.token != address(0)) {
            require(_tokenGate.minAmount > 0, "Min amt cannot be 0");
            _setTokenGate(auction, _tokenGate.token, _tokenGate.minAmount);
        }

        if (_startTime > 0) {
            require(_startTime > block.timestamp, "Start time must be in the future");
            require(_expiry == 0 || _expiry > _startTime, "Start time cannot be after expiry");
            _setStartTime(auction, _startTime);
        }

        if (_bidCurrency != address(0)) {
            _setERC20Currency(auction, _bidCurrency);
        }

        // Store the auction metadata
        auction.seller = tokenOwner;
        auction.reservePrice = _reservePrice;
        auction.duration = _duration;

        FullAuction memory fullAuction = _getFullAuction(_tokenContract, _tokenId);
        emit AuctionCreated(_tokenContract, _tokenId, fullAuction);
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

        if (ongoingAuctionForNFT[_tokenContract][_tokenId].firstBidTime > 0) {
            revert("Auction started");
        }

        // Ensure the caller is the seller
        require(msg.sender == auction.seller, "ONLY_SELLER");

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
        require(ongoingAuctionForNFT[_tokenContract][_tokenId].firstBidTime == 0, "AUCTION_STARTED");

        // Ensure the caller is the seller or a new owner of the token
        require(msg.sender == auction.seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "ONLY_SELLER_OR_TOKEN_OWNER");

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
        require(seller != address(0), "AUCTION_DOES_NOT_EXIST");

        // Cache features
        uint32 features = auction.features;

        if (_hasFeature(features, FEATURE_MASK_START_TIME)) {
            uint256 startTime = _getStartTime(auction);
            require(block.timestamp >= startTime, "AUCTION_NOT_STARTED");
        }

        if (_hasFeature(auction.features, FEATURE_MASK_TOKEN_GATE)) {
            ReserveAuctionDataStorage.TokenGate memory tokenGate = _getTokenGate(auction);
            require(IERC20(tokenGate.token).balanceOf(msg.sender) >= tokenGate.minAmount, "Token gate not satisfied");
        }

        // Used to emit whether the bid started the auction
        bool firstBid;

        OngoingAuction memory ongoingAuction = ongoingAuctionForNFT[_tokenContract][_tokenId];

        address currency = _getERC20CurrencyWithFallback(auction);

        // If this is the first bid, start the auction
        if (ongoingAuction.firstBidTime == 0) {
            // Ensure the bid meets the reserve price
            require(_amount >= auction.reservePrice, "RESERVE_PRICE_NOT_MET");

            if (_hasFeature(auction.features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
                (uint96 expiry, ) = _getExpiryAndFundsRecipient(auction);
                require(expiry == 0 || expiry >= block.timestamp, "Auction has expired");
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
            require(block.timestamp < (ongoingAuction.firstBidTime + auction.duration), "AUCTION_OVER");

            // Cache the highest bid
            uint256 highestBid = ongoingAuction.highestBid;

            // Used to store the minimum bid required to outbid the highest bidder
            uint256 minValidBid;

            // Calculate the minimum bid required (10% higher than the highest bid)
            // TODO: audit overflow potential now that prices are uint256
            unchecked {
                minValidBid = highestBid + ((highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100);
            }

            // Ensure the incoming bid meets the minimum
            require(_amount >= minValidBid, "MINIMUM_BID_NOT_MET");

            // Refund the previous bidder
            _handleOutgoingTransfer(ongoingAuction.highestBidder, highestBid, currency, 50000);

            ongoingAuction.highestBid = _amount;
            ongoingAuction.highestBidder = msg.sender;
        }

        if (_hasFeature(auction.features, FEATURE_MASK_FINDERS_FEE)) {
            uint16 findersFeeBps = (_getFindersFee(auction)).findersFeeBps;
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

        // If the bid is placed within 15 minutes of the auction end, extend the auction
        if (timeRemaining < TIME_BUFFER) {
            // Add (15 minutes - remaining time) to the duration so that 15 minutes remain
            // Cannot underflow as `timeRemaining` is ensured to be less than `TIME_BUFFER`
            unchecked {
                auction.duration += uint64(TIME_BUFFER - timeRemaining);
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
            ListingFee memory listingFeeInfo = _getListingFee(auction);
            listingFee = (remainingProfit * listingFeeInfo.listingFeeBps) / 10000;
            listingFeeRecipient = listingFeeInfo.listingFeeRecipient;
        }

        if (_hasFeature(auction.features, FEATURE_MASK_FINDERS_FEE)) {
            FindersFee memory findersFeeAndRecipient = _getFindersFee(auction);
            if (findersFeeAndRecipient.finder != address(0)) {
                finder = findersFeeAndRecipient.finder;
                uint16 findersFeeBps = findersFeeAndRecipient.findersFeeBps;
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
        require(firstBidTime != 0, "AUCTION_NOT_STARTED");

        // Ensure the auction has ended
        require(block.timestamp >= (firstBidTime + auction.duration), "AUCTION_NOT_OVER");

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
