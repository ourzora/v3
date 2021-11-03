// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

// ============ Imports ============

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";
import {CollectionRoyaltyRegistryV1} from "../../CollectionRoyaltyRegistry/V1/CollectionRoyaltyRegistryV1.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to make an offer on any ERC-721
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1 {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    CollectionRoyaltyRegistryV1 royaltyRegistry;
    IWETH weth;

    // ============ Mutable Storage ============

    /// @notice The NFT collection offers created by a given user
    /// @dev User address => collection offer ID
    mapping(address => uint256[]) public userToCollectionOffers;

    /// @notice The NFT offers created by a given user
    /// @dev User address => NFT offer ID
    mapping(address => uint256[]) public userToNFTOffers;

    /// @notice The offers for a given NFT collection
    /// @dev NFT address => offer IDs
    mapping(address => uint256[]) public collectionToOffers;

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public nftToOffers;

    /// @notice Whether a user has an active offer for a given collection
    /// @dev User address => NFT address => boolean
    mapping(address => mapping(address => bool)) public userHasActiveCollectionOffer;

    /// @notice Whether a user has an active offer for a given NFT
    /// @dev User address => NFT address => NFT ID => boolean
    mapping(address => mapping(address => mapping(uint256 => bool))) public userHasActiveNFTOffer;

    /// @notice A mapping of IDs to their respective collection offer
    mapping(uint256 => CollectionOffer) public collectionOffers;

    /// @notice A mapping of IDs to their respective NFT offer
    mapping(uint256 => NFTOffer) public nftOffers;

    Counters.Counter collectionOfferCounter;
    Counters.Counter nftOfferCounter;

    enum OfferStatus {
        Active,
        Canceled,
        Filled
    }

    struct CollectionOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 offerPrice;
        uint8 findersFeePercentage;
        OfferStatus status;
    }

    struct NFTOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 tokenID;
        uint256 offerPrice;
        uint8 findersFeePercentage;
        OfferStatus status;
    }

    // ============ Events ============

    event CollectionOfferCreated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferPriceUpdated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferCanceled(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferFilled(uint256 indexed id, address seller, address finder, CollectionOffer offer);

    event NFTOfferCreated(uint256 indexed id, NFTOffer offer);
    event NFTOfferPriceUpdated(uint256 indexed id, NFTOffer offer);
    event NFTOfferCanceled(uint256 indexed id, NFTOffer offer);
    event NFTOfferFilled(uint256 indexed id, address seller, address finder, NFTOffer offer);

    // ============ Constructor ============

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
        royaltyRegistry = CollectionRoyaltyRegistryV1(_royaltyRegistry);
        zoraV1Media = IZoraV1Media(_zoraV1ProtocolMedia);
        zoraV1Market = IZoraV1Market(zoraV1Media.marketContract());
        weth = IWETH(_wethAddress);
    }

    // ============ Create Offers ============

    /// @notice Places an offer on a NFT collection
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created collection offer
    function createCollectionOffer(
        address _tokenContract,
        uint256 _offerPrice,
        address _offerCurrency,
        uint8 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        require(userHasActiveCollectionOffer[msg.sender][_tokenContract] == false, "createCollectionOffer must update or cancel existing offer");
        require(_findersFeePercentage <= 100, "createCollectionOffer finders fee percentage must be less than 100");
        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        collectionOfferCounter.increment();
        uint256 offerId = collectionOfferCounter.current();

        collectionOffers[offerId] = CollectionOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            offerPrice: _offerPrice,
            findersFeePercentage: _findersFeePercentage,
            status: OfferStatus.Active
        });

        userToCollectionOffers[msg.sender].push(offerId);
        collectionToOffers[_tokenContract].push(offerId);
        userHasActiveCollectionOffer[msg.sender][_tokenContract] = true;

        emit CollectionOfferCreated(offerId, collectionOffers[offerId]);

        return offerId;
    }

    /// @notice Places an offer on a NFT
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenID The ID of the ERC-721 token to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created NFT offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenID,
        uint256 _offerPrice,
        address _offerCurrency,
        uint8 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenID) != msg.sender, "createNFTOffer cannot make offer on NFT you own");
        require(userHasActiveNFTOffer[msg.sender][_tokenContract][_tokenID] == false, "createNFTOffer must update or cancel existing offer");
        require(_findersFeePercentage <= 100, "createNFTOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        nftOfferCounter.increment();
        uint256 offerID = nftOfferCounter.current();

        nftOffers[offerID] = NFTOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenID: _tokenID,
            offerPrice: _offerPrice,
            findersFeePercentage: _findersFeePercentage,
            status: OfferStatus.Active
        });

        userToNFTOffers[msg.sender].push(offerID);
        nftToOffers[_tokenContract][_tokenID].push(offerID);
        userHasActiveNFTOffer[msg.sender][_tokenContract][_tokenID] = true;

        emit NFTOfferCreated(offerID, nftOffers[offerID]);

        return offerID;
    }

    // ============ Update Offers ============

    /// @notice Updates the price of a collection offer
    /// @param _offerID The ID of the collection offer
    /// @param _newOffer The new offer price
    function setCollectionOfferPrice(uint256 _offerID, uint256 _newOffer) external payable nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerID];

        require(offer.buyer == msg.sender, "setCollectionOfferPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setCollectionOfferPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit CollectionOfferPriceUpdated(_offerID, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency);
            offer.offerPrice -= decreaseAmount;

            emit CollectionOfferPriceUpdated(_offerID, offer);
        }
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerID The ID of the NFT offer
    /// @param _newOffer The new offer price
    function setNFTOfferPrice(uint256 _offerID, uint256 _newOffer) external payable nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.buyer == msg.sender, "setNFTOfferPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setNFTOfferPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit NFTOfferPriceUpdated(_offerID, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency);
            offer.offerPrice -= decreaseAmount;

            emit NFTOfferPriceUpdated(_offerID, offer);
        }
    }

    // ============ Cancel Offers ============

    /// @notice Cancels a collection offer
    /// @param _offerID The ID of the collection offer
    function cancelCollectionOffer(uint256 _offerID) external nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerID];

        require(offer.buyer == msg.sender, "cancelCollectionOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelCollectionOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userHasActiveCollectionOffer[offer.buyer][offer.tokenContract] = false;

        emit CollectionOfferCanceled(_offerID, offer);
    }

    /// @notice Cancels a NFT offer
    /// @param _offerID The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerID) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelNFTOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userHasActiveNFTOffer[offer.buyer][offer.tokenContract][offer.tokenID] = false;

        emit NFTOfferCanceled(_offerID, offer);
    }

    // ============ Fill Offers ============

    /// @notice Fills a collection offer
    /// @param _offerID The ID of the collection offer
    /// @param _tokenID The ID of the NFT to transfer
    /// @param _finder The address of the referrer for this offer
    function fillCollectionOffer(
        uint256 _offerID,
        uint256 _tokenID,
        address _finder
    ) external nonReentrant {
        CollectionOffer storage collectionOffer = collectionOffers[_offerID];

        require(collectionOffer.status == OfferStatus.Active, "fillCollectionOffer must be active offer");
        require(_finder != address(0), "fillCollectionOffer _finder must not be 0 address");
        require(msg.sender == IERC721(collectionOffer.tokenContract).ownerOf(_tokenID), "fillCollectionOffer must own token associated with offer");

        // Convert to NFTOffer for royalty payouts
        NFTOffer memory offer = _convertFilledCollectionOffer(collectionOffer, _tokenID);

        uint256 remainingProfit = offer.offerPrice;
        if (offer.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(offer);
        } else if (IERC165(offer.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(offer);
        } else {
            remainingProfit = _handleRoyaltyRegistryPayout(offer);
        }

        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;
        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency);

        remainingProfit = remainingProfit - finderFee;

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, _tokenID);

        collectionOffer.status = OfferStatus.Filled;
        userHasActiveCollectionOffer[offer.buyer][offer.tokenContract] = false;

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenID, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerPrice});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit CollectionOfferFilled(_offerID, msg.sender, _finder, collectionOffer);
    }

    /// @notice Fills a NFT offer
    /// @param _offerID The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTOffer(uint256 _offerID, address _finder) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.status == OfferStatus.Active, "fillNFTOffer must be active offer");
        require(_finder != address(0), "fillNFTOffer _finder must not be 0 address");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenID), "fillNFTOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        uint256 remainingProfit = offer.offerPrice;

        if (offer.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(offer);
        } else if (IERC165(offer.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(offer);
        } else {
            remainingProfit = _handleRoyaltyRegistryPayout(offer);
        }

        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;
        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency);

        remainingProfit = remainingProfit - finderFee;

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenID);

        offer.status = OfferStatus.Filled;
        userHasActiveNFTOffer[offer.buyer][offer.tokenContract][offer.tokenID] = false;

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenID, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerPrice});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_offerID, msg.sender, _finder, offer);
    }

    // ============ Private ============

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
            require((beforeBalance + _amount) == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
        }
    }

    /// @notice Handle an outgoing funds transfer
    /// @dev Wraps ETH in WETH if the receiver cannot receive ETH, noop if the funds to be sent are 0 or recipient is invalid
    /// @param _dest The destination for the funds
    /// @param _amount The amount to be sent
    /// @param _currency The currency to send funds in, or address(0) for ETH
    function _handleOutgoingTransfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        if (_amount == 0 || _dest == address(0)) {
            return;
        }
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

    /// @notice Pays out royalties for ZORA NFTs
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleZoraPayout(NFTOffer memory offer) private returns (uint256) {
        IZoraV1Market.BidShares memory bidShares = zoraV1Market.bidSharesForToken(offer.tokenID);

        uint256 creatorProfit = zoraV1Market.splitShare(bidShares.creator, offer.offerPrice);
        uint256 prevOwnerProfit = zoraV1Market.splitShare(bidShares.prevOwner, offer.offerPrice);
        uint256 remainingProfit = offer.offerPrice - creatorProfit - prevOwnerProfit;

        // Pay out creator
        _handleOutgoingTransfer(zoraV1Media.tokenCreators(offer.tokenID), creatorProfit, offer.offerCurrency);
        // Pay out prev owner
        _handleOutgoingTransfer(zoraV1Media.previousTokenOwners(offer.tokenID), prevOwnerProfit, offer.offerCurrency);

        return remainingProfit;
    }

    /// @notice Pays out royalties for EIP-2981 compliant NFTs
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleEIP2981Payout(NFTOffer memory offer) private returns (uint256) {
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(offer.tokenContract).royaltyInfo(offer.tokenID, offer.offerPrice);

        uint256 remainingProfit = offer.offerPrice - royaltyAmount;

        _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, offer.offerCurrency);

        return remainingProfit;
    }

    /// @notice Pays out royalties for collections
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleRoyaltyRegistryPayout(NFTOffer memory offer) private returns (uint256) {
        (address royaltyReceiver, uint8 royaltyPercentage) = royaltyRegistry.collectionRoyalty(offer.tokenContract);

        uint256 remainingProfit = offer.offerPrice;
        uint256 royaltyAmount = (remainingProfit * royaltyPercentage) / 100;
        _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, offer.offerCurrency);

        remainingProfit -= royaltyAmount;

        return remainingProfit;
    }

    /// @notice Converts an accepted collection offer to a NFT offer to use as a reference for the royalty calculations
    /// @param _collectionOffer The accepted collection offer
    /// @param _tokenID The NFT ID to complete the conversion
    /// @return The offer to use as a reference for the royalty calculations
    function _convertFilledCollectionOffer(CollectionOffer memory _collectionOffer, uint256 _tokenID) private pure returns (NFTOffer memory) {
        return
            NFTOffer({
                buyer: _collectionOffer.buyer,
                offerCurrency: _collectionOffer.offerCurrency,
                tokenContract: _collectionOffer.tokenContract,
                tokenID: _tokenID,
                offerPrice: _collectionOffer.offerPrice,
                findersFeePercentage: _collectionOffer.findersFeePercentage,
                status: OfferStatus.Filled
            });
    }
}
