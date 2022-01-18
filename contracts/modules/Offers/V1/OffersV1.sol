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
/// @notice This module allows buyers to place ETH/ERC-20 offers for any ERC-721 token
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The number of offers placed
    uint256 public offerCount;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata of an offer
    /// @param buyer The address of the buyer placing the offer
    /// @param currency The address of the ERC-20, or address(0) for ETH, denominating the offer
    /// @param tokenContract The address of the ERC-721 token to be purchased
    /// @param findersFeeBps The fee to the referrer of the offer
    /// @param tokenId The ID of the ERC-721 token to be purchased
    /// @param amount The amount offered
    struct Offer {
        address buyer;
        address currency;
        address tokenContract;
        uint16 findersFeeBps;
        uint256 tokenId;
        uint256 amount;
    }

    /// ------------ STORAGE ------------

    /// @notice The metadata for a given offer
    /// @dev Offer ID => Offer
    mapping(uint256 => Offer) public offers;

    /// @notice The offers for a given NFT
    /// @dev ERC-721 token address => ERC-721 token ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// ------------ EVENTS ------------

    /// @notice Emitted when an offer is created
    /// @param id The ID of the created offer
    /// @param offer The metadata of the created offer
    event NFTOfferCreated(uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is updated
    /// @param id The ID of the updated offer
    /// @param offer The metadata of the updated offer
    event NFTOfferAmountUpdated(uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is canceled
    /// @param id The ID of the canceled offer
    /// @param offer The metadata of the canceled offer
    event NFTOfferCanceled(uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is filled
    /// @param id The ID of the filled offer
    /// @param seller The address of the seller who filled the offer
    /// @param finder The address of the finder who referred the offer
    /// @param offer The metadata of the filled offer
    event NFTOfferFilled(uint256 indexed id, address indexed seller, address indexed finder, Offer offer);

    /// ------------ CONSTRUCTOR ------------

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZoraProtocolFeeSettingsV1 address
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
        ModuleNamingSupportV1("Offers: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Creates an offer for a NFT
    /// @param _tokenContract The address of the ERC-721 token to be purchased
    /// @param _tokenId The ID of the ERC-721 token to be purchased
    /// @param _amount The amount to offer
    /// @param _currency The address of the ERC-20 token being offered, or address(0) for ETH
    /// @param _findersFeeBps The bps of the offer amount (post-royalties) to be sent to the referrer of the sale
    /// @return The ID of the created offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _currency,
        uint16 _findersFeeBps
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createNFTOffer cannot place offer on own NFT");
        require(_findersFeeBps <= 10000, "createNFTOffer finders fee bps must be less than or equal to 10000");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_amount, _currency);

        offerCount++;

        offers[offerCount] = Offer({
            buyer: msg.sender,
            currency: _currency,
            tokenContract: _tokenContract,
            findersFeeBps: _findersFeeBps,
            tokenId: _tokenId,
            amount: _amount
        });

        offersForNFT[_tokenContract][_tokenId].push(offerCount);

        emit NFTOfferCreated(offerCount, offers[offerCount]);

        return offerCount;
    }

    /// @notice Updates the amount of an offer
    /// @param _offerId The ID of the offer
    /// @param _amount The new offer amount
    function setNFTOfferAmount(uint256 _offerId, uint256 _amount) external payable nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "setNFTOfferAmount must be buyer");
        require((_amount != 0) && (_amount != offer.amount), "setNFTOfferAmount _amount cannot be 0 or previous amount");

        uint256 prevAmount = offer.amount;
        if (_amount > prevAmount) {
            uint256 increaseAmount = _amount - prevAmount;
            _handleIncomingTransfer(increaseAmount, offer.currency);

            offer.amount += increaseAmount;
        } else if (_amount < prevAmount) {
            uint256 decreaseAmount = prevAmount - _amount;
            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.currency, USE_ALL_GAS_FLAG);

            offer.amount -= decreaseAmount;
        }

        emit NFTOfferAmountUpdated(_offerId, offer);
    }

    /// @notice Cancels and refunds the offer for an NFT
    /// @param _offerId The ID of the offer
    function cancelNFTOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer");

        _handleOutgoingTransfer(offer.buyer, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        emit NFTOfferCanceled(_offerId, offer);

        delete offers[_offerId];
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Fills the offer for an NFT, transferring the ETH/ERC-20 to the seller and NFT to the buyer
    /// @param _offerId The ID of the offer
    /// @param _finder The address of the offer referrer
    function fillNFTOffer(uint256 _offerId, address _finder) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer != address(0), "fillNFTOffer must be active offer");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenId), "fillNFTOffer must be token owner");

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, offer.currency);

        // Payout optional finder fee
        if (_finder != address(0)) {
            uint256 finderFee = (remainingProfit * offer.findersFeeBps) / 10000;
            _handleOutgoingTransfer(_finder, finderFee, offer.currency, USE_ALL_GAS_FLAG);

            remainingProfit -= finderFee;
        }

        // Transfer remaining ETH/ERC-20 to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.currency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.currency, tokenId: 0, amount: offer.amount});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_offerId, msg.sender, _finder, offer);

        delete offers[_offerId];
    }
}
