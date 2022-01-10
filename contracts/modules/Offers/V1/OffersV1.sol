// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to make offers on any ERC-721 token
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1 {
    using Counters for Counters.Counter;

    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The total number of offers
    Counters.Counter public offerCounter;

    /// @notice An individual offer
    struct Offer {
        address buyer;
        address currency;
        address tokenContract;
        uint256 tokenId;
        uint256 amount;
        uint256 findersFeePercentage;
    }

    /// ------------ PUBLIC STORAGE ------------

    /// @notice A mapping of IDs to their respective offer
    mapping(uint256 => Offer) public offers;

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// ------------ EVENTS ------------

    event NFTOfferCreated(uint256 indexed id, Offer offer);

    event NFTOfferAmountUpdated(uint256 indexed id, Offer offer);

    event NFTOfferCanceled(uint256 indexed id, Offer offer);

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
    ) IncomingTransferSupportV1(_erc20TransferHelper) FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _wethAddress) {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Places an offer on a NFT
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenId The ID of the ERC-721 token to place the offer
    /// @param _amount The price of the offer
    /// @param _currency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created NFT offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _currency,
        uint256 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createNFTOffer cannot make offer on owned NFT");
        require(_findersFeePercentage <= 100, "createNFTOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_amount, _currency);

        offerCounter.increment();
        uint256 offerId = offerCounter.current();

        offers[offerId] = Offer({
            buyer: msg.sender,
            currency: _currency,
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            amount: _amount,
            findersFeePercentage: _findersFeePercentage
        });

        offersForNFT[_tokenContract][_tokenId].push(offerId);

        emit NFTOfferCreated(offerId, offers[offerId]);

        return offerId;
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _newAmount The new offer price
    function setNFTOfferAmount(uint256 _offerId, uint256 _newAmount) external payable nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "setNFTOfferAmount offer must be active and caller must be original buyer");
        require((_newAmount > 0) && (_newAmount != offer.amount), "setNFTOfferAmount _newAmount must be greater than 0 and not equal to previous offer");

        uint256 prevOffer = offer.amount;

        if (_newAmount > prevOffer) {
            uint256 increaseAmount = _newAmount - prevOffer;
            _handleIncomingTransfer(increaseAmount, offer.currency);

            offer.amount += increaseAmount;
        } else if (_newAmount < prevOffer) {
            uint256 decreaseAmount = prevOffer - _newAmount;
            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.currency, USE_ALL_GAS_FLAG);

            offer.amount -= decreaseAmount;
        }

        emit NFTOfferAmountUpdated(_offerId, offer);
    }

    /// @notice Cancels a NFT offer
    /// @param _offerId The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "cancelNFTOffer offer must be active and caller must be original buyer");

        _handleOutgoingTransfer(offer.buyer, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        emit NFTOfferCanceled(_offerId, offer);

        delete offers[_offerId];
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Fills a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTOffer(uint256 _offerId, address _finder) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer != address(0), "fillNFTOffer must be active offer");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenId), "fillNFTOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.amount, offer.currency, USE_ALL_GAS_FLAG);
        remainingProfit = _handleProtocolFeePayout(remainingProfit, offer.currency);

        if (_finder != address(0)) {
            uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;
            _handleOutgoingTransfer(_finder, finderFee, offer.currency, USE_ALL_GAS_FLAG);

            remainingProfit -= finderFee;
        }

        // Transfer sale proceeds to seller
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
