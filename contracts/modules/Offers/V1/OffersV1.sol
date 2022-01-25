// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows users to place ETH/ERC-20 offers for any ERC-721 token
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The number of offers placed
    uint256 public offerCount;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata of an offer
    /// @param seller The address of the seller placing the offer
    /// @param currency The address of the ERC-20 selling, or address(0) for ETH
    /// @param findersFeeBps The fee to the referrer of the offer
    /// @param amount The amount selling
    struct Offer {
        address seller;
        address currency;
        uint16 findersFeeBps;
        uint256 amount;
    }

    /// ------------ STORAGE ------------

    /// @notice The metadata for a given offer
    /// @dev ERC-721 token address => ERC-721 token ID => Offer ID => Offer
    mapping(address => mapping(uint256 => mapping(uint256 => Offer))) public offers;

    /// @notice The offers for a given NFT
    /// @dev ERC-721 token address => ERC-721 token ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// ------------ EVENTS ------------

    /// @notice Emitted when an offer is created
    /// @param tokenContract The ERC-721 token address of the created offer
    /// @param tokenId The ERC-721 token ID of the created offer
    /// @param id The ID of the created offer
    /// @param offer The metadata of the created offer
    event NFTOfferCreated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is updated
    /// @param tokenContract The ERC-721 token address of the updated offer
    /// @param tokenId The ERC-721 token ID of the updated offer
    /// @param id The ID of the updated offer
    /// @param offer The metadata of the updated offer
    event NFTOfferAmountUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is canceled
    /// @param tokenContract The ERC-721 token address of the canceled offer
    /// @param tokenId The ERC-721 token ID of the canceled offer
    /// @param id The ID of the canceled offer
    /// @param offer The metadata of the canceled offer
    event NFTOfferCanceled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is filled
    /// @param tokenContract The ERC-721 token address of the filled offer
    /// @param tokenId The ERC-721 token ID of the filled offer
    /// @param id The ID of the filled offer
    /// @param buyer The address of the buyer who filled the offer
    /// @param finder The address of the finder who referred the offer
    /// @param offer The metadata of the filled offer
    event NFTOfferFilled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, address buyer, address finder, Offer offer);

    /// ------------ CONSTRUCTOR ------------

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZoraProtocolFeeSettingsV1 address
    /// @param _wethAddress The WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _wethAddress
    )
        IncomingTransferSupportV1(_erc20TransferHelper)
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _wethAddress, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Offers: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Creates an offer for an NFT
    /// @param _tokenContract The address of the desired ERC-721 token
    /// @param _tokenId The ID of the desired ERC-721 token
    /// @param _currency The address of the offering ERC-20 token, or address(0) for ETH
    /// @param _amount The amount offering
    /// @param _findersFeeBps The bps of the amount (post-royalties) to send to a referrer of the sale
    /// @return The ID of the created offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        address _currency,
        uint256 _amount,
        uint16 _findersFeeBps
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createNFTOffer cannot place offer on own NFT");
        require(_findersFeeBps <= 10000, "createNFTOffer finders fee bps must be less than or equal to 10000");

        // Ensure valid payment and take custody of offer
        _handleIncomingTransfer(_amount, _currency);

        // Get offer ID
        offerCount++;

        // Store offer metadata
        offers[_tokenContract][_tokenId][offerCount] = Offer({
            seller: msg.sender,
            currency: _currency,
            findersFeeBps: _findersFeeBps,
            amount: _amount
        });

        // Add ID to offers placed for NFT
        offersForNFT[_tokenContract][_tokenId].push(offerCount);

        emit NFTOfferCreated(_tokenContract, _tokenId, offerCount, offers[_tokenContract][_tokenId][offerCount]);

        return offerCount;
    }

    /// @notice Updates the amount of an offer
    /// @param _tokenContract The address of the offer ERC-721 token
    /// @param _tokenId The ID of the offer ERC-721 token
    /// @param _offerId The ID of the offer
    /// @param _amount The new offer amount
    function setNFTOfferAmount(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        uint256 _amount
    ) external payable nonReentrant {
        Offer storage offer = offers[_tokenContract][_tokenId][offerCount];

        require(offer.seller == msg.sender, "setNFTOfferAmount must be seller");
        require(_amount != 0 && _amount != offer.amount, "setNFTOfferAmount _amount cannot be 0 or previous amount");

        // Get initial offer
        uint256 prevAmount = offer.amount;

        // If update is increase --
        if (_amount > prevAmount) {
            // Ensure valid payment and take custody
            uint256 increaseAmount = _amount - prevAmount;
            _handleIncomingTransfer(increaseAmount, offer.currency);

            // Increase offer
            offer.amount += increaseAmount;

            // If update is decrease --
        } else if (_amount < prevAmount) {
            // Refund difference
            uint256 decreaseAmount = prevAmount - _amount;
            _handleOutgoingTransfer(offer.seller, decreaseAmount, offer.currency, USE_ALL_GAS_FLAG);

            // Decrease offer
            offer.amount -= decreaseAmount;
        }

        emit NFTOfferAmountUpdated(_tokenContract, _tokenId, _offerId, offer);
    }

    /// @notice Cancels and refunds the offer for an NFT
    /// @param _tokenContract The ERC-721 token address of the offer
    /// @param _tokenId The ERC-721 token ID of the offer
    /// @param _offerId The ID of the offer
    function cancelNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external nonReentrant {
        Offer storage offer = offers[_tokenContract][_tokenId][offerCount];

        require(offer.seller == msg.sender, "cancelNFTOffer must be seller");

        // Refund offered amount
        _handleOutgoingTransfer(offer.seller, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        emit NFTOfferCanceled(_tokenContract, _tokenId, _offerId, offer);

        delete offers[_tokenContract][_tokenId][offerCount];
    }

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Fills the offer for an owned NFT, in exchange for ETH/ERC-20 tokens
    /// @param _tokenContract The address of the ERC-721 token to sell
    /// @param _tokenId The ID of the ERC-721 token to sell
    /// @param _offerId The ID of the offer to fill
    /// @param _currency The address of ERC-20 token to accept, or address(0) for ETH
    /// @param _amount The offered amount to accept
    /// @param _finder The address of the offer referrer
    function fillNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _currency,
        uint256 _amount,
        address _finder
    ) external nonReentrant {
        Offer storage offer = offers[_tokenContract][_tokenId][offerCount];

        require(offer.seller != address(0), "fillNFTOffer must be active offer");
        require(IERC721(_tokenContract).ownerOf(_tokenId) == msg.sender, "fillNFTOffer must be token owner");
        require(offer.currency == _currency, "fillNFTOffer _currency must match offer currency");
        require(offer.amount == _amount, "fillNFTOffer _amount must match offer amount");

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, offer.currency);

        // Payout optional finders fee
        if (_finder != address(0)) {
            uint256 findersFee = (remainingProfit * offer.findersFeeBps) / 10000;
            _handleOutgoingTransfer(_finder, findersFee, offer.currency, USE_ALL_GAS_FLAG);

            remainingProfit -= findersFee;
        }

        // Transfer remaining ETH/ERC-20 to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.currency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.seller, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.currency, tokenId: 0, amount: offer.amount});

        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});

        emit ExchangeExecuted(offer.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_tokenContract, _tokenId, _offerId, msg.sender, _finder, offer);

        delete offers[_tokenContract][_tokenId][offerCount];
    }
}
