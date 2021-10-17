// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";
import {RoyaltyRegistryV1} from "../../RoyaltyRegistry/V1/RoyaltyRegistryV1.sol";

/// @title Listings V1
/// @author tbtstl <t@zora.co>
/// @notice This module allows sellers to list an owned ERC-721 token for sale for a given price in a given currency, and allows buyers to purchase from those listings
contract ListingsV1 is ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;
    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IWETH weth;
    RoyaltyRegistryV1 royaltyRegistry;

    Counters.Counter listingCounter;

    /// @notice The listings created by a given user
    mapping(address => uint256[]) public listingsForUser;

    /// @notice The listing for a given NFT, if one exists
    /// @dev NFT address => NFT ID => listing ID
    mapping(address => mapping(uint256 => uint256)) public listingForNFT;

    /// @notice A mapping of IDs to their respective listing
    mapping(uint256 => Listing) public listings;

    enum ListingStatus {
        Active,
        Canceled,
        Filled
    }

    struct Listing {
        address tokenContract;
        address seller;
        address fundsRecipient;
        address listingCurrency;
        address host;
        uint256 tokenId;
        uint256 listingPrice;
        uint8 listingFeePercentage;
        uint8 findersFeePercentage;
        ListingStatus status;
    }

    event ListingCreated(uint256 indexed id, Listing listing);
    event ListingPriceUpdated(uint256 indexed id, Listing listing);
    event ListingCanceled(uint256 indexed id, Listing listing);
    event ListingFilled(uint256 indexed id, address buyer, Listing listing);

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
        erc20TransferHelper = ERC20TransferHelper(_erc20TransferHelper);
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
        zoraV1Media = IZoraV1Media(_zoraV1ProtocolMedia);
        zoraV1Market = IZoraV1Market(zoraV1Media.marketContract());
        weth = IWETH(_wethAddress);
        royaltyRegistry = RoyaltyRegistryV1(_royaltyRegistry);
    }

    /// @notice Lists an NFT for sale
    /// @param _tokenContract The address of the ERC-721 token contract for the token to be sold
    /// @param _tokenId The ERC-721 token ID for the token to be sold
    /// @param _listingPrice The price of the sale
    /// @param _listingCurrency The address of the ERC-20 token to accept an offer in, or address(0) for ETH
    /// @param _fundsRecipient The address to send funds to once the token is sold
    /// @param _host The host of the sale, who can receive _listingFeePercentage of the sale price
    /// @param _listingFeePercentage The percentage of the sale amount to be sent to the host
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created listing
    function createListing(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _listingPrice,
        address _listingCurrency,
        address _fundsRecipient,
        address _host,
        uint8 _listingFeePercentage,
        uint8 _findersFeePercentage
    ) external nonReentrant returns (uint256) {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            tokenOwner == msg.sender ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) == true ||
                IERC721(_tokenContract).getApproved(_tokenId) == msg.sender,
            "createListing must be token owner or approved operator"
        );
        require(_fundsRecipient != address(0), "createListing must specify fundsRecipient");
        require(_listingFeePercentage.add(_findersFeePercentage) <= 100, "createListing listing fee and finders fee percentage must be less than 100");

        // Create a listing
        listingCounter.increment();
        uint256 listingId = listingCounter.current();
        listings[listingId] = Listing({
            tokenContract: _tokenContract,
            seller: msg.sender,
            fundsRecipient: _fundsRecipient,
            listingCurrency: _listingCurrency,
            host: _host,
            tokenId: _tokenId,
            listingPrice: _listingPrice,
            listingFeePercentage: _listingFeePercentage,
            findersFeePercentage: _findersFeePercentage,
            status: ListingStatus.Active
        });

        // Register listing lookup helpers
        listingsForUser[msg.sender].push(listingId);
        listingForNFT[_tokenContract][_tokenId] = listingId;

        emit ListingCreated(listingId, listings[listingId]);

        return listingId;
    }

    /// @notice Updates the listing price for a given listing
    /// @param _listingId the ID of the listing to update
    /// @param _listingPrice the price to update the listing to
    /// @param _listingCurrency The address of the ERC-20 token to accept an offer in, or address(0) for ETH
    function setListingPrice(
        uint256 _listingId,
        uint256 _listingPrice,
        address _listingCurrency
    ) external {
        Listing storage listing = listings[_listingId];

        require(listing.seller == msg.sender, "setListingPrice must be seller");
        require(listing.status == ListingStatus.Active, "setListingPrice must be active listing");

        listing.listingPrice = _listingPrice;
        listing.listingCurrency = _listingCurrency;

        emit ListingPriceUpdated(_listingId, listing);
    }

    /// @notice Cancels a listing
    /// @param _listingId the ID of the listing to cancel
    function cancelListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];

        require(
            listing.seller == msg.sender || IERC721(listing.tokenContract).ownerOf(listing.tokenId) != listing.seller,
            "cancelListing must be seller or invalid listing"
        );
        require(listing.status == ListingStatus.Active, "cancelListing must be active listing");

        // Set listing status to cancelled
        listing.status = ListingStatus.Canceled;

        emit ListingCanceled(_listingId, listing);
    }

    /// @notice Purchase an NFT from a listing, transferring the NFT to the buyer and funds to the recipients
    /// @param _listingId The ID of the listing
    /// @param _finder The address of the referrer for this listing
    function fillListing(uint256 _listingId, address _finder) external payable nonReentrant {
        Listing storage listing = listings[_listingId];

        require(listing.seller != address(0), "fillListing listing does not exist");
        require(_finder != address(0), "fillListing _finder must not be 0 address");
        require(listing.status == ListingStatus.Active, "fillListing must be active listing");

        // Ensure payment is valid and take custody of payment
        _handleIncomingTransfer(listing.listingPrice, listing.listingCurrency);

        // Payout respective parties, ensuring royalties are honored
        uint256 remainingProfit = listing.listingPrice;
        if (listing.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(listing);
        } else if (IERC165(listing.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(listing);
        } else {
            remainingProfit = _handleRoyaltyRegistryPayout(listing);
        }

        uint256 hostProfit = remainingProfit.mul(listing.listingFeePercentage).div(100);
        uint256 finderFee = remainingProfit.mul(listing.findersFeePercentage).div(100);

        if (hostProfit != 0 && listing.host != address(0)) {
            _handleOutgoingTransfer(listing.host, hostProfit, listing.listingCurrency);
        }
        if (finderFee != 0) {
            _handleOutgoingTransfer(_finder, finderFee, listing.listingCurrency);
        }

        _handleOutgoingTransfer(listing.fundsRecipient, remainingProfit.sub(hostProfit).sub(finderFee), listing.listingCurrency);

        // Transfer NFT to auction winner
        erc721TransferHelper.transferFrom(listing.tokenContract, listing.seller, msg.sender, listing.tokenId);

        listing.status = ListingStatus.Filled;

        emit ListingFilled(_listingId, msg.sender, listing);
    }

    /// @notice Pays out royalties for ZORA NFTs
    /// @param listing The listing to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleZoraPayout(Listing memory listing) private returns (uint256) {
        IZoraV1Market.BidShares memory bidShares = zoraV1Market.bidSharesForToken(listing.tokenId);

        uint256 creatorProfit = zoraV1Market.splitShare(bidShares.creator, listing.listingPrice);
        uint256 prevOwnerProfit = zoraV1Market.splitShare(bidShares.prevOwner, listing.listingPrice);
        uint256 remainingProfit = listing.listingPrice.sub(creatorProfit).sub(prevOwnerProfit);

        // Pay out creator
        if (creatorProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.tokenCreators(listing.tokenId), creatorProfit, listing.listingCurrency);
        }
        // Pay out prev owner
        if (prevOwnerProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.previousTokenOwner(listing.tokenId), prevOwnerProfit, listing.listingCurrency);
        }

        return remainingProfit;
    }

    /// @notice Pays out royalties for EIP-2981 compliant NFTs
    /// @param listing The listing to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleEIP2981Payout(Listing memory listing) private returns (uint256) {
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(listing.tokenContract).royaltyInfo(listing.tokenId, listing.listingPrice);

        uint256 remainingProfit = listing.listingPrice.sub(royaltyAmount);

        if (royaltyAmount != 0 && royaltyReceiver != address(0)) {
            _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, listing.listingCurrency);
        }

        return remainingProfit;
    }

    /// @notice Pays out royalties for collections
    /// @param listing The listing to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleRoyaltyRegistryPayout(Listing memory listing) private returns (uint256) {
        (address royaltyReceiver, uint8 royaltyPercentage) = royaltyRegistry.collectionRoyalty(listing.tokenContract);

        uint256 remainingProfit = listing.listingPrice;

        if (royaltyReceiver != address(0) && royaltyPercentage != 0) {
            uint256 royaltyAmount = remainingProfit.mul(100).div(royaltyPercentage);
            _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, listing.listingCurrency);

            remainingProfit -= royaltyAmount;
        }

        return remainingProfit;
    }

    /// @notice Handle an incoming funds transfer, ensuring the sent amount is valid and the sender is solvent
    /// @param _amount The amount to be received
    /// @param _currency The currency to receive funds in, or address(0) for ETH
    function _handleIncomingTransfer(uint256 _amount, address _currency) private {
        if (_currency == address(0)) {
            require(msg.value >= _amount, "_handleIncomingTransfer msg value less than expected amount");
        } else {
            // We must check the balance that was actually transferred to this contract,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            erc20TransferHelper.safeTransferFrom(_currency, msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            require(beforeBalance.add(_amount) == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
        }
    }

    /// @notice Handle an outgoing funds transfer
    /// @dev Wraps ETH in WETH if the receiver cannot receive ETH
    /// @param _dest The destination for the funds
    /// @param _amount The amount to be sent
    /// @param _currency The currency to send funds in, or address(0) for ETH
    function _handleOutgoingTransfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        // Handle ETH payment
        if (_currency == address(0)) {
            require(address(this).balance >= _amount, "_handleOutgoingTransfer insolvent");
            // Here increase the gas limit a reasonable amount above the default, and try
            // to send ETH to the recipient.
            (bool success, ) = _dest.call{value: _amount, gas: 30000}(new bytes(0));

            // If the ETH transfer fails (sigh), wrap the ETH and try send it as WETH.
            if (!success) {
                weth.deposit{value: _amount}();
                IERC20(address(weth)).safeTransfer(_dest, _amount);
            }
        } else {
            IERC20(_currency).safeTransfer(_dest, _amount);
        }
    }
}
