// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

// ============ Imports ============

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to make an offer on any ERC-721
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    using Counters for Counters.Counter;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;
    ERC721TransferHelper erc721TransferHelper;

    Counters.Counter collectionOfferCounter;
    Counters.Counter nftOfferCounter;
    Counters.Counter nftGroupOfferCounter;

    /// ============ NFT Offers Storage ============

    /// @notice The NFT offers created by a given user
    /// @dev User address => NFT offer id
    mapping(address => uint256[]) public nftOffersPerUser;

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer ids
    mapping(address => mapping(uint256 => uint256[])) public offersPerNFT;

    /// @notice A mapping of IDs to their respective NFT offer
    mapping(uint256 => NFTOffer) public nftOffers;

    /// ============ NFT Group Offers Storage ============

    /// @notice The NFT group offers created by a given user
    /// @dev User address => NFT group offer id
    mapping(address => uint256[]) public nftGroupOffersPerUser;

    /// @notice The offers for any of the specified NFTs in a given collection
    /// @dev NFT address => offer ids
    mapping(address => uint256[]) public offersPerNFTGroup;

    /// @notice A mapping of ids to their respective NFT group offer
    mapping(uint256 => NFTGroupOffer) public nftGroupOffers;

    /// ============ Collection Offers Storage ============

    /// @notice The NFT collection offers created by a given user
    /// @dev User address => collection offer id
    mapping(address => uint256[]) public collectionOffersPerUser;

    /// @notice The offers for a given NFT collection
    /// @dev NFT address => offer ids
    mapping(address => uint256[]) public offersPerCollection;

    /// @notice A mapping of IDs to their respective collection offer
    mapping(uint256 => CollectionOffer) public collectionOffers;

    /// @notice All offer IDs on a collection with the same offer currency and offer amount
    /// @dev Collection address => Offer Currency address => Offer Price uint256 => Offer IDs
    mapping(address => mapping(address => mapping(uint256 => uint256[]))) public collectionOrderBook;

    /// @notice The (continuously updated) starting index to parse and update offer IDs in `collectionOrderBook`
    /// @dev Collection address => Offer Currency address => Offer Price uint256 => Starting Index
    mapping(address => mapping(address => mapping(uint256 => uint256))) public collectionOrderBookStartingIndex;

    /// @notice A collection offer ID to its index location in the associated `collectionOrderBook` array
    /// @dev Offer ID => Index
    mapping(uint256 => uint256) public collectionOfferToOrderBookIndex;

    /// ============ Enums ============

    enum OfferStatus {
        Active,
        Canceled,
        Filled
    }

    /// ============ Structs ============

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
        uint256 tokenId;
        uint256 offerPrice;
        uint8 findersFeePercentage;
        OfferStatus status;
    }

    struct NFTGroupOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256[] tokenIDs;
        uint256 offerPrice;
        uint8 findersFeePercentage;
        OfferStatus status;
    }

    /// ============ Events ============

    event CollectionOfferCreated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferPriceUpdated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferCanceled(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferFilled(uint256 indexed id, address indexed seller, address indexed finder, CollectionOffer offer);

    event NFTOfferCreated(uint256 indexed id, NFTOffer offer);
    event NFTOfferPriceUpdated(uint256 indexed id, NFTOffer offer);
    event NFTOfferCanceled(uint256 indexed id, NFTOffer offer);
    event NFTOfferFilled(uint256 indexed id, address indexed seller, address indexed finder, NFTOffer offer);

    event NFTGroupOfferCreated(uint256 indexed id, NFTGroupOffer offer);
    event NFTGroupOfferPriceUpdated(uint256 indexed id, NFTGroupOffer offer);
    event NFTGroupOfferCanceled(uint256 indexed id, NFTGroupOffer offer);
    event NFTGroupOfferFilled(uint256 indexed id, address indexed seller, address indexed finder, NFTGroupOffer offer);

    /// ============ Constructor ============

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _wethAddress WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _wethAddress
    ) IncomingTransferSupportV1(_erc20TransferHelper) RoyaltyPayoutSupportV1(_royaltyEngine, _wethAddress) {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ============ Create Offers ============

    /// @notice Places an offer on any NFT from a collection
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

        _addToOrderBook(offerId, _tokenContract, _offerCurrency, _offerPrice);

        collectionOffersPerUser[msg.sender].push(offerId);
        offersPerCollection[_tokenContract].push(offerId);

        emit CollectionOfferCreated(offerId, collectionOffers[offerId]);

        return offerId;
    }

    /// @notice Places an offer on any NFT
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenId The ID of the ERC-721 token to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created NFT offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerPrice,
        address _offerCurrency,
        uint8 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        require(msg.sender != IERC721(_tokenContract).ownerOf(_tokenId), "createNFTOffer cannot make offer on NFT you own");
        require(_findersFeePercentage <= 100, "createNFTOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        nftOfferCounter.increment();
        uint256 offerID = nftOfferCounter.current();

        nftOffers[offerID] = NFTOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            offerPrice: _offerPrice,
            findersFeePercentage: _findersFeePercentage,
            status: OfferStatus.Active
        });

        nftOffersPerUser[msg.sender].push(offerID);
        offersPerNFT[_tokenContract][_tokenId].push(offerID);

        emit NFTOfferCreated(offerID, nftOffers[offerID]);

        return offerID;
    }

    /// @notice Places an offer on any of the specified NFTs in a collection
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenIDs The IDs of the ERC-721 tokens to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created NFT offer
    function createNFTGroupOffer(
        address _tokenContract,
        uint256[] memory _tokenIDs,
        uint256 _offerPrice,
        address _offerCurrency,
        uint8 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        for (uint256 i; i < _tokenIDs.length; i++) {
            require(msg.sender != IERC721(_tokenContract).ownerOf(_tokenIDs[i]), "createNFTGroupOffer cannot make offer on NFT you own");
        }
        require(_findersFeePercentage <= 100, "createNFTGroupOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        nftGroupOfferCounter.increment();
        uint256 offerId = nftGroupOfferCounter.current();

        nftGroupOffers[offerId] = NFTGroupOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenIDs: _tokenIDs,
            offerPrice: _offerPrice,
            findersFeePercentage: _findersFeePercentage,
            status: OfferStatus.Active
        });

        nftGroupOffersPerUser[msg.sender].push(offerId);
        offersPerNFTGroup[_tokenContract].push(offerId);

        emit NFTGroupOfferCreated(offerId, nftGroupOffers[offerId]);

        return offerId;
    }

    /// ============ Update Offers ============

    /// @notice Updates the price of a collection offer
    /// @param _offerId The ID of the collection offer
    /// @param _newOffer The new offer price
    function setCollectionOfferPrice(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerId];

        require(offer.buyer == msg.sender, "setCollectionOfferPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setCollectionOfferPrice must be active offer");

        uint256 prevAmount = offer.offerPrice;
        if (_newOffer > prevAmount) {
            uint256 increaseAmount = _newOffer - prevAmount;

            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit CollectionOfferPriceUpdated(_offerId, offer);
        } else if (_newOffer < prevAmount) {
            uint256 decreaseAmount = prevAmount - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency, 0);

            offer.offerPrice -= decreaseAmount;

            emit CollectionOfferPriceUpdated(_offerId, offer);
        }

        // Mark previous offer as inactive in order book
        _removeFromOrderBook(_offerId, offer.tokenContract, offer.offerCurrency, prevAmount);
        // Add new offer to order book
        _addToOrderBook(_offerId, offer.tokenContract, offer.offerCurrency, offer.offerPrice);
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _newOffer The new offer price
    function setNFTOfferPrice(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.buyer == msg.sender, "setNFTOfferPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setNFTOfferPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit NFTOfferPriceUpdated(_offerId, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency, 0);
            offer.offerPrice -= decreaseAmount;

            emit NFTOfferPriceUpdated(_offerId, offer);
        }
    }

    /// @notice Updates the price of a NFT group offer
    /// @param _offerId The ID of the NFT group offer
    /// @param _newOffer The new offer price
    function setNFTGroupOfferPrice(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        NFTGroupOffer storage offer = nftGroupOffers[_offerId];

        require(offer.buyer == msg.sender, "setNFTGroupOfferPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setNFTGroupOfferPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit NFTGroupOfferPriceUpdated(_offerId, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency, 0);
            offer.offerPrice -= decreaseAmount;

            emit NFTGroupOfferPriceUpdated(_offerId, offer);
        }
    }

    /// ============ Cancel Offers ============

    /// @notice Cancels a collection offer
    /// @param _offerId The ID of the collection offer
    function cancelCollectionOffer(uint256 _offerId) external nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerId];

        require(offer.buyer == msg.sender, "cancelCollectionOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelCollectionOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency, 0);

        offer.status = OfferStatus.Canceled;

        _removeFromOrderBook(_offerId, offer.tokenContract, offer.offerCurrency, offer.offerPrice);

        emit CollectionOfferCanceled(_offerId, offer);
    }

    /// @notice Cancels a NFT offer
    /// @param _offerId The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerId) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelNFTOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency, 0);

        offer.status = OfferStatus.Canceled;

        emit NFTOfferCanceled(_offerId, offer);
    }

    /// @notice Cancels a NFT group offer
    /// @param _offerId The ID of the NFT group offer
    function cancelNFTGroupOffer(uint256 _offerId) external nonReentrant {
        NFTGroupOffer storage offer = nftGroupOffers[_offerId];

        require(offer.buyer == msg.sender, "cancelNFTGroupOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelNFTGroupOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency, 0);

        offer.status = OfferStatus.Canceled;

        emit NFTGroupOfferCanceled(_offerId, offer);
    }

    /// ============ Fill Offers ============

    /// @notice Fills a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTOffer(uint256 _offerId, address _finder) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.status == OfferStatus.Active, "fillNFTOffer must be active offer");
        require(_finder != address(0), "fillNFTOffer _finder must not be 0 address");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenId), "fillNFTOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        uint256 remainingProfit = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.offerPrice, offer.offerCurrency, 0);

        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;
        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency, 0);

        remainingProfit = remainingProfit - finderFee;

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency, 0);
        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        offer.status = OfferStatus.Filled;

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenID, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerPrice});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_offerId, msg.sender, _finder, offer);
    }

    /// @notice Fills a NFT offer from a buyer-specified set of token IDs
    /// @param _offerId The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTGroupOffer(
        uint256 _offerId,
        uint256 _tokenId,
        address _finder
    ) external nonReentrant {
        NFTGroupOffer memory nftGroupOffer = nftGroupOffers[_offerId];

        require(nftGroupOffer.status == OfferStatus.Active, "fillNFTGroupOffer must be active offer");
        require(_finder != address(0), "fillNFTGroupOffer _finder must not be 0 address");

        bool valid;
        for (uint256 i; i < nftGroupOffer.tokenIDs.length; i++) {
            if (nftGroupOffer.tokenIDs[i] == _tokenId) {
                valid = true;
                break;
            }
        }
        require(valid, "fillNFTGroupOffer _tokenId must be in group offer");
        require(msg.sender == IERC721(nftGroupOffer.tokenContract).ownerOf(_tokenId), "fillNFTGroupOffer must own token associated with offer");

        // Convert to NFTOffer for royalty payouts
        NFTOffer memory offer = NFTOffer({
            buyer: nftGroupOffer.buyer,
            offerCurrency: nftGroupOffer.offerCurrency,
            tokenContract: nftGroupOffer.tokenContract,
            tokenId: _tokenId,
            offerPrice: nftGroupOffer.offerPrice,
            findersFeePercentage: nftGroupOffer.findersFeePercentage,
            status: OfferStatus.Filled
        });

        uint256 remainingProfit = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.offerPrice, offer.offerCurrency, 0);
        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;

        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency, 0);
        remainingProfit = remainingProfit - finderFee;

        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency, 0);
        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        nftGroupOffer.status = OfferStatus.Filled;

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenID, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerPrice});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTGroupOfferFilled(_offerId, msg.sender, _finder, nftGroupOffer);
    }

    /// @notice Fills a specified or equivalent (if exists) collection offer
    /// @param _offerId The ID of the collection offer
    /// @param _tokenId The ID of the NFT to transfer
    /// @param _finder The address of the referrer for this offer
    function fillCollectionOffer(
        uint256 _offerId,
        uint256 _tokenId,
        address _finder
    ) external nonReentrant {
        require(_finder != address(0), "fillCollectionOffer _finder must not be 0 address");

        CollectionOffer storage collectionOffer = collectionOffers[_offerId];

        require(msg.sender == IERC721(collectionOffer.tokenContract).ownerOf(_tokenId), "fillCollectionOffer must own token associated with offer");

        uint256 offerId = _offerId;

        // If specified _offerId has been filled, check order book for any equivalent, active offers
        if (collectionOffer.status == OfferStatus.Filled) {
            offerId = _getMatchInOrderBook(collectionOffer.tokenContract, collectionOffer.offerCurrency, collectionOffer.offerPrice);
        }
        collectionOffer = collectionOffers[offerId];

        require(collectionOffer.status == OfferStatus.Active, "fillCollectionOffer must be active offer");

        // Convert to NFTOffer for royalty payouts
        NFTOffer memory offer = NFTOffer({
            buyer: collectionOffer.buyer,
            offerCurrency: collectionOffer.offerCurrency,
            tokenContract: collectionOffer.tokenContract,
            tokenId: _tokenId,
            offerPrice: collectionOffer.offerPrice,
            findersFeePercentage: collectionOffer.findersFeePercentage,
            status: OfferStatus.Filled
        });

        uint256 remainingProfit = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.offerPrice, offer.offerCurrency, 0);
        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;

        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency, 0);

        remainingProfit = remainingProfit - finderFee;

        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency, 0);
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        collectionOffer.status = OfferStatus.Filled;

        _removeFromOrderBook(offerId, offer.tokenContract, offer.offerCurrency, offer.offerPrice);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerPrice});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit CollectionOfferFilled(offerId, msg.sender, _finder, collectionOffer);
    }

    // ============ Private ============

    /// @notice Adds a created or updated collection offer to the offer book
    /// @param _offerId The id of the collection offer
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _offerPrice The price of the offer
    function _addToOrderBook(
        uint256 _offerId,
        address _tokenContract,
        address _offerCurrency,
        uint256 _offerPrice
    ) private {
        collectionOrderBook[_tokenContract][_offerCurrency][_offerPrice].push(_offerId);
        collectionOfferToOrderBookIndex[_offerId] = collectionOrderBook[_tokenContract][_offerCurrency][_offerPrice].length - 1;
    }

    /// @notice Retrieves an equivalent offer (if exists) to fill
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _offerPrice The price of the offer
    function _getMatchInOrderBook(
        address _tokenContract,
        address _offerCurrency,
        uint256 _offerPrice
    ) private returns (uint256) {
        uint256 matchingOfferId;
        bool found;

        // Get updated starting index to avoid redundant parsing
        uint256 startIndex = collectionOrderBookStartingIndex[_tokenContract][_offerCurrency][_offerPrice];
        uint256[] memory equalOffers = collectionOrderBook[_tokenContract][_offerCurrency][_offerPrice];

        for (uint256 i = startIndex; i < equalOffers.length; i++) {
            // If active offers (> 0) exists store its offerId
            if (equalOffers[i] > 0) {
                matchingOfferId = equalOffers[i];
                found = true;

                // Store i+1 as starting index for next lookup
                collectionOrderBookStartingIndex[_tokenContract][_offerCurrency][_offerPrice] = i + 1;
                break;
            }
        }
        // Throw error if equivalent offer not found
        require(found, "fillCollectionOffer this offer and all equals have been filled.");

        return matchingOfferId;
    }

    /// @notice Removes an active collection offer from the offer book
    /// @param _offerId The id of the collection offer
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _offerPrice The price of the offer
    function _removeFromOrderBook(
        uint256 _offerId,
        address _tokenContract,
        address _offerCurrency,
        uint256 _offerPrice
    ) private {
        uint256 index = collectionOfferToOrderBookIndex[_offerId];

        require(_offerId == collectionOrderBook[_tokenContract][_offerCurrency][_offerPrice][index], "_removeFromOrderBook offerId and index do not match");

        delete collectionOrderBook[_tokenContract][_offerCurrency][_offerPrice][index];
        delete collectionOfferToOrderBookIndex[_offerId];
    }
}
