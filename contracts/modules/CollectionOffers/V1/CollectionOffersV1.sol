// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {CollectionOfferBookV1} from "./CollectionOfferBookV1.sol";

/// @title Collection Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to place offers for any NFT from an ERC-721 collection, and allows sellers to fill an offer
contract CollectionOffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1, CollectionOfferBookV1 {
    address private constant ETH = address(0);
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// ------------ EVENTS ------------

    event CollectionOfferCreated(uint256 indexed id, Offer offer);

    event CollectionOfferPriceUpdated(uint256 indexed id, Offer offer);

    event CollectionOfferCanceled(uint256 indexed id, Offer offer);

    event CollectionOfferFilled(uint256 indexed id, address indexed seller, address indexed finder, Offer offer);

    /// ------------ CONSTRUCTOR ------------

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

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Places an offer for any NFT in a collection
    /// @param _tokenContract The ERC-721 collection address
    /// @return The ID of the created offer
    function createCollectionOffer(address _tokenContract) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "createCollectionOffer msg value must be greater than 0");

        _handleIncomingTransfer(msg.value, ETH);

        uint256 offerId = _addOffer(_tokenContract, msg.value, msg.sender);

        emit CollectionOfferCreated(offerId, offers[_tokenContract][offerId]);

        return offerId;
    }

    /// @notice Updates the price of a collection offer
    /// @param _tokenContract The ERC-721 collection address
    /// @param _offerId The ID of the created offer
    /// @param _newOfferAmount The new offer price
    function setCollectionOfferAmount(
        address _tokenContract,
        uint256 _offerId,
        uint256 _newOfferAmount
    ) external payable nonReentrant {
        require(offers[_tokenContract][_offerId].active, "setCollectionOfferAmount must be active offer");
        require(msg.sender == offers[_tokenContract][_offerId].buyer, "setCollectionOfferAmount msg sender must be buyer");
        uint256 prevOfferAmount = offers[_tokenContract][_offerId].offerAmount;
        require(
            (_newOfferAmount > 0) && (_newOfferAmount != prevOfferAmount),
            "setCollectionOfferAmount _newOfferAmount must be greater than 0 and not equal to previous offer"
        );

        if (_newOfferAmount > prevOfferAmount) {
            uint256 increaseAmount = _newOfferAmount - prevOfferAmount;

            _handleIncomingTransfer(increaseAmount, ETH);
            _updateOffer(_tokenContract, _offerId, _newOfferAmount, true);
        } else if (_newOfferAmount < prevOfferAmount) {
            uint256 decreaseAmount = prevOfferAmount - _newOfferAmount;

            _handleOutgoingTransfer(msg.sender, decreaseAmount, ETH, USE_ALL_GAS_FLAG);
            _updateOffer(_tokenContract, _offerId, _newOfferAmount, false);
        }

        emit CollectionOfferPriceUpdated(_offerId, offers[_tokenContract][_offerId]);
    }

    /// @notice Cancels a collection offer
    /// @param _tokenContract The ERC-721 collection address
    /// @param _offerId The ID of the created offer
    function cancelCollectionOffer(address _tokenContract, uint256 _offerId) external nonReentrant {
        require(offers[_tokenContract][_offerId].active, "cancelCollectionOffer must be active offer");
        require(msg.sender == offers[_tokenContract][_offerId].buyer, "cancelCollectionOffer msg sender must be buyer");

        _handleOutgoingTransfer(msg.sender, offers[_tokenContract][_offerId].offerAmount, ETH, USE_ALL_GAS_FLAG);

        emit CollectionOfferCanceled(_offerId, offers[_tokenContract][_offerId]);

        _removeOffer(_tokenContract, _offerId);
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Fills the highest collection offer available, above a specified minimum
    /// @param _tokenContract The ERC-721 collection address
    /// @param _tokenId The ID of the seller's collection NFT
    /// @param _minAmount The minimum offer price the seller is willing to accept
    /// @param _finder The address of the referrer for this fill
    function fillCollectionOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _minAmount,
        address _finder
    ) external nonReentrant {
        require(_finder != address(0), "fillCollectionOffer _finder must not be 0 address");
        require(msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "fillCollectionOffer msg sender must own specified token");

        (bool matchFound, uint256 offerId) = _getMatchingOffer(_tokenContract, _minAmount);
        require(matchFound, "fillCollectionOffer offer satisfying specified _minAmount not found");

        Offer memory offer = offers[_tokenContract][offerId];

        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, offer.offerAmount, ETH, USE_ALL_GAS_FLAG);
        uint256 finderFee = remainingProfit / 100; // 1% finder's fee

        _handleOutgoingTransfer(_finder, finderFee, ETH, USE_ALL_GAS_FLAG);

        remainingProfit -= finderFee;

        _handleOutgoingTransfer(msg.sender, remainingProfit, ETH, USE_ALL_GAS_FLAG);

        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.buyer, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: ETH, tokenId: 0, amount: offer.offerAmount});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit CollectionOfferFilled(offerId, msg.sender, _finder, offer);

        _removeOffer(_tokenContract, offerId);
    }
}
