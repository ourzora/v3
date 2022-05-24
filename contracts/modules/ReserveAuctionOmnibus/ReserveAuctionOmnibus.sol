// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

import {IReserveAuctionOmnibus} from "./IReserveAuctionOmnibus.sol";
import {AuctionDataStorage} from "./AuctionDataStorage.sol";

/// @title Reserve Auction
/// @author kulkarohan
/// @notice Module adding Listing Fee to Reserve Auction Core ERC-20
contract ReserveAuctionOmnibus is ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1, AuctionDataStorage {
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint16 constant TIME_BUFFER = 15 minutes;

    /// @notice The minimum percentage difference between two bids
    uint8 constant MIN_BID_INCREMENT_PERCENTAGE = 10;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata for a given auction
    /// @param seller The address of the seller
    /// @param reservePrice The reserve price to start the auction
    /// @param sellerFundsRecipient The address where funds are sent after the auction
    /// @param highestBid The highest bid of the auction
    /// @param highestBidder The address of the highest bidder
    /// @param startTime The time that the first bid can be placed
    /// @param currency The address of the ERC-20 token, or address(0) for ETH, required to place a bid
    /// @param firstBidTime The time that the first bid is placed
    /// @param listingFeeRecipient The address that listed the auction
    /// @param duration The length of time that the auction runs after the first bid is placed
    /// @param listingFeeBps The fee that is sent to the lister of the auction

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
        ModuleNamingSupportV1("Reserve Auction Listing ERC-20")
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

    /**
        createAuctionWithSig
        createAskWithSig
     */

    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _duration The length of time the auction should run after the first bid
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the auction is complete
    /// @param _startTime The time that users can begin placing bids
    /// @param _bidCurrency The address of the ERC-20 token, or address(0) for ETH, that users must bid with
    /// @param _startTime startTime
    /// @param _bidCurrency bid currency
    /// @param _findersFeeBps sadf
    /// @param _listingFee sdf
    /// @param _tokenGate asdf
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint256 _startTime,
        address _bidCurrency,
        uint16 _findersFeeBps,
        AuctionDataStorage.ListingFee memory _listingFee,
        AuctionDataStorage.AuctionTokenGate memory _tokenGate
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        // Ensure the reserve price can be downcasted to 96 bits for this module
        // For a higher reserve price, use the supporting module
        require(_reservePrice <= type(uint96).max, "INVALID_RESERVE_PRICE");

        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Clear features (if re-used from another auction on the same token)
        auction.features = 0;

        if (_sellerFundsRecipient != address(0)) {
            _setSellerFundsRecipient(auction, _sellerFundsRecipient);
        }

        if (_listingFee.listingFeeBps > 0) {
            // Ensure the listing fee does not exceed 10,000 basis points
            require(_listingFee.listingFeeBps <= 10000, "INVALID_LISTING_FEE");
            _setListingFee(auction, _listingFee.listingFeeBps, _listingFee.listingFeeRecipient);
        }

        if (_tokenGate.token != address(0)) {
            require(_tokenGate.minAmount > 0, "Min amt cannot be 0");
            _setAuctionTokenGate(auction, _tokenGate.token, _tokenGate.minAmount);
        }

        if (_startTime > 0) {
            _setStartTime(auction, _startTime);
        }

        if (_bidCurrency != address(0)) {
            _setERC20Currency(auction, _bidCurrency);
        }

        // Store the auction metadata
        auction.seller = tokenOwner;
        auction.reservePrice = uint96(_reservePrice);
        auction.duration = uint80(_duration);
        auction.findersFeeBps = _findersFeeBps;

        emit AuctionCreated(_tokenContract, _tokenId, _getFullAuction(auction));
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

        // Ensure the reserve price can be downcasted to 96 bits
        require(_reservePrice <= type(uint96).max, "INVALID_RESERVE_PRICE");

        // Update the reserve price
        auction.reservePrice = uint96(_reservePrice);

        emit AuctionReservePriceUpdated(_tokenContract, _tokenId, _getFullAuction(auction));
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

        emit AuctionCanceled(_tokenContract, _tokenId, _getFullAuction(auction));

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
        uint256 _amount
    ) external payable nonReentrant {
        // Get the auction for the specified token
        StoredAuction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = auction.seller;

        // Ensure the auction exists
        require(seller != address(0), "AUCTION_DOES_NOT_EXIST");

        // Cache features
        uint32 features = auction.features;

        if (_hasFeature(features, FEATURE_MASK_SET_START_TIME)) {
            uint256 startTime = _getStartTime(auction);
            require(block.timestamp >= startTime, "AUCTION_NOT_STARTED");
        }

        // Ensure the bid can be downcasted to 96 bits for this module
        // For a higher bid, use the supporting module
        require(_amount <= type(uint96).max, "INVALID_BID");

        // Used to emit whether the bid started the auction
        bool firstBid;

        OngoingAuction memory ongoingAuction = ongoingAuctionForNFT[_tokenContract][_tokenId];

        address currency = _getERC20CurrencyWithFallback(auction);

        // If this is the first bid, start the auction
        if (ongoingAuction.firstBidTime == 0) {
            // Ensure the bid meets the reserve price
            require(_amount >= auction.reservePrice, "RESERVE_PRICE_NOT_MET");

            // Store the amount as the highest bid
            ongoingAuction = OngoingAuction({highestBid: uint96(_amount), highestBidder: msg.sender, firstBidTime: uint96(block.timestamp)});

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
            // Cannot overflow as `minValidBid` cannot be greater than 104 bits
            unchecked {
                minValidBid = highestBid + ((highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100);
            }

            // Ensure the result can be downcasted to 96 bits
            require(minValidBid <= type(uint96).max, "MAX_BID_PLACED");

            // Ensure the incoming bid meets the minimum
            require(_amount >= minValidBid, "MINIMUM_BID_NOT_MET");

            // Refund the previous bidder
            _handleOutgoingTransfer(ongoingAuction.highestBidder, highestBid, currency, 50000);

            ongoingAuction.highestBid = uint96(_amount);
            ongoingAuction.highestBidder = msg.sender;
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
                auction.duration += uint80(TIME_BUFFER - timeRemaining);
            }

            // Mark the bid as one that extended the auction
            extended = true;
        }

        ongoingAuctionForNFT[_tokenContract][_tokenId] = ongoingAuction;

        emit AuctionBid(_tokenContract, _tokenId, firstBid, extended, _getFullAuction(auction));
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

        // Cache the listing fee recipient
        // Payout the listing fee, if a recipient exists
        if (_hasFeature(auction.features, FEATURE_MASK_LISTING_FEE)) {
            ListingFee memory listingFeeInfo = _getListingFee(auction);
            // Get the listing fee from the remaining profit
            uint256 listingFee = (remainingProfit * listingFeeInfo.listingFeeBps) / 10000;

            // Transfer the amount to the listing fee recipient
            _handleOutgoingTransfer(listingFeeInfo.listingFeeRecipient, listingFee, currency, 50000);

            // Update the remaining profit
            remainingProfit -= listingFee;
        }

        // TODO(): add finders fee

        // Transfer the remaining profit to the funds recipient
        _handleOutgoingTransfer(
            _hasFeature(auction.features, FEATURE_MASK_FUNDS_RECIPIENT) ? _getSellerFundsRecipient(auction) : auction.seller,
            remainingProfit,
            currency,
            50000
        );

        // Transfer the NFT to the winning bidder
        IERC721(_tokenContract).transferFrom(address(this), ongoingAuction.highestBidder, _tokenId);

        emit AuctionEnded(_tokenContract, _tokenId, _getFullAuction(auction));

        // Remove the auction from storage
        delete auctionForNFT[_tokenContract][_tokenId];
        // Remove the auction ongoing state from storage
        delete ongoingAuctionForNFT[_tokenContract][_tokenId];
    }
}
