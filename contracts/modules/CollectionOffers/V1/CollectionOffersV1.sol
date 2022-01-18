// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {OutgoingTransferSupportV1} from "../../../common/OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {CollectionOfferBookV1} from "./CollectionOfferBookV1.sol";

/// @title Collection Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to place offers for any NFT from an ERC-721 collection, and allows sellers to fill an offer
contract CollectionOffersV1 is
    ReentrancyGuard,
    UniversalExchangeEventV1,
    IncomingTransferSupportV1,
    FeePayoutSupportV1,
    ModuleNamingSupportV1,
    CollectionOfferBookV1
{
    /// @dev The indicator to denominate all transfers in ETH
    address private constant ETH = address(0);
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// ------------ EVENTS ------------

    /// @notice Emitted when a collection offer is created
    /// @param collection The ERC-721 token address of the created offer
    /// @param id The ID of the created offer
    /// @param offer The metadata of the created offer
    event CollectionOfferCreated(address indexed collection, uint256 indexed id, Offer offer);

    /// @notice Emitted when a collection offer is updated
    /// @param collection The ERC-721 token address of the updated offer
    /// @param id The ID of the updated offer
    /// @param offer The metadata of the updated offer
    event CollectionOfferPriceUpdated(address indexed collection, uint256 indexed id, Offer offer);

    /// @notice Emitted when the finders fee for a collection offer is updated
    /// @param collection The ERC-721 token address of the updated offer
    /// @param id The ID of the updated offer
    /// @param findersFeeBps The bps of the updated finders fee
    /// @param offer The metadata of the updated offer
    event CollectionOfferFindersFeeUpdated(address indexed collection, uint256 indexed id, uint16 indexed findersFeeBps, Offer offer);

    /// @notice Emitted when a collection offer is canceled
    /// @param collection The ERC-721 token address of the canceled offer
    /// @param id The ID of the canceled offer
    /// @param offer The metadata of the canceled offer
    event CollectionOfferCanceled(address indexed collection, uint256 indexed id, Offer offer);

    /// @notice Emitted when a collection offer is filled
    /// @param collection The ERC-721 token address of the filled offer
    /// @param id The ID of the filled offer
    /// @param seller The address of the seller who filled the offer
    /// @param finder The address of the finder who referred the sale
    /// @param offer The metadata of the canceled offer
    event CollectionOfferFilled(address indexed collection, uint256 indexed id, address seller, address finder, Offer offer);

    /// ------------ CONSTRUCTOR ------------

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _wethAddress WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _wethAddress
    )
        IncomingTransferSupportV1(_erc20TransferHelper)
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _wethAddress, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Collection Offers: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ NFT BUYER FUNCTIONS ------------

    /// @notice Places an offer for any NFT in a collection
    /// @param _tokenContract The ERC-721 collection address
    /// @return The ID of the created offer
    function createCollectionOffer(address _tokenContract) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "createCollectionOffer msg value must be greater than 0");

        // Ensure offer is valid and take custody
        _handleIncomingTransfer(msg.value, ETH);

        uint256 offerId = _addOffer(_tokenContract, msg.value, msg.sender);

        emit CollectionOfferCreated(_tokenContract, offerId, offers[_tokenContract][offerId]);

        return offerId;
    }

    /// @notice Updates the price of a collection offer
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _offerId The ID of the created offer
    /// @param _newAmount The new offer
    function setCollectionOfferAmount(
        address _tokenContract,
        uint256 _offerId,
        uint256 _newAmount
    ) external payable nonReentrant {
        require(msg.sender == offers[_tokenContract][_offerId].buyer, "setCollectionOfferAmount offer must be active & msg sender must be buyer");
        require(
            (_newAmount > 0) && (_newAmount != offers[_tokenContract][_offerId].amount),
            "setCollectionOfferAmount _newAmount must be greater than 0 and not equal to previous offer"
        );
        uint256 prevAmount = offers[_tokenContract][_offerId].amount;

        if (_newAmount > prevAmount) {
            uint256 increaseAmount = _newAmount - prevAmount;
            require(msg.value == increaseAmount, "setCollectionOfferAmount must send exact increase amount");

            _handleIncomingTransfer(increaseAmount, ETH);
            _updateOffer(_tokenContract, _offerId, _newAmount, true);
        } else if (_newAmount < prevAmount) {
            uint256 decreaseAmount = prevAmount - _newAmount;

            _handleOutgoingTransfer(msg.sender, decreaseAmount, ETH, USE_ALL_GAS_FLAG);
            _updateOffer(_tokenContract, _offerId, _newAmount, false);
        }

        emit CollectionOfferPriceUpdated(_tokenContract, _offerId, offers[_tokenContract][_offerId]);
    }

    /// @notice Updates the finders fee of a collection offer
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _offerId The ID of the created offer
    /// @param _findersFeeBps The new finders fee bps
    function setCollectionOfferFindersFee(
        address _tokenContract,
        uint256 _offerId,
        uint16 _findersFeeBps
    ) external nonReentrant {
        require(msg.sender == offers[_tokenContract][_offerId].buyer, "setCollectionOfferFindersFee msg sender must be buyer");
        require((_findersFeeBps > 1) && (_findersFeeBps <= 10000), "setCollectionOfferFindersFee must be less than or equal to 10000 bps");

        findersFeeOverrides[_tokenContract][_offerId] = _findersFeeBps;

        emit CollectionOfferFindersFeeUpdated(_tokenContract, _offerId, _findersFeeBps, offers[_tokenContract][_offerId]);
    }

    /// @notice Cancels a collection offer
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _offerId The ID of the created offer
    function cancelCollectionOffer(address _tokenContract, uint256 _offerId) external nonReentrant {
        require(msg.sender == offers[_tokenContract][_offerId].buyer, "cancelCollectionOffer offer must be active & msg sender must be buyer");

        _handleOutgoingTransfer(msg.sender, offers[_tokenContract][_offerId].amount, ETH, USE_ALL_GAS_FLAG);

        emit CollectionOfferCanceled(_tokenContract, _offerId, offers[_tokenContract][_offerId]);

        _removeOffer(_tokenContract, _offerId);
    }

    /// ------------ NFT SELLER FUNCTIONS ------------

    /// @notice Fills the highest collection offer available, if above the desired minimum
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _minAmount The minimum amount willing to accept
    /// @param _finder The address of the referrer for this sale
    function fillCollectionOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _minAmount,
        address _finder
    ) external nonReentrant {
        require(_finder != address(0), "fillCollectionOffer _finder must not be 0 address");
        require(msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "fillCollectionOffer msg sender must own specified token");

        // Get matching offer (if exists)
        uint256 offerId = _getMatchingOffer(_tokenContract, _minAmount);
        require(offerId > 0, "fillCollectionOffer offer satisfying specified _minAmount not found");

        Offer memory offer = offers[_tokenContract][offerId];

        // Ensure royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, offer.amount, ETH, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, ETH);

        // Payout optional finder fee
        if (_finder != address(0)) {
            uint256 findersFee;

            // If no override, payout default 100 bps finders fee
            if (findersFeeOverrides[_tokenContract][offerId] == 0) {
                findersFee = (remainingProfit * 100) / 10000;
                // Else payout with override
            } else {
                findersFee = (remainingProfit * findersFeeOverrides[_tokenContract][offerId]) / 10000;
            }
            _handleOutgoingTransfer(_finder, findersFee, ETH, USE_ALL_GAS_FLAG);

            remainingProfit -= findersFee;
        }

        // Transfer remaining ETH to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, ETH, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.buyer, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: ETH, tokenId: 0, amount: offer.amount});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit CollectionOfferFilled(_tokenContract, offerId, msg.sender, _finder, offer);

        _removeOffer(_tokenContract, offerId);
    }
}
