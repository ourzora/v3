// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

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
/// @notice This module allows buyers to make offers on any ERC-721 token
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    using Counters for Counters.Counter;

    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice An individual offer
    struct Offer {
        bool active;
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 tokenId;
        uint256 offerAmount;
        uint8 findersFeePercentage;
    }

    /// @notice The total number of offers
    Counters.Counter public offerCounter;

    /// ------------ STORAGE ------------

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// @notice The index a given offer is stored in offersForNFT
    /// @dev NFT Address => NFT ID => offer ID => index
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private offerToIndex;

    /// @notice A mapping of IDs to their respective offer
    mapping(uint256 => Offer) public offers;

    /// ------------ EVENTS ------------

    event NFTOfferCreated(uint256 indexed id, Offer offer);

    event NFTOfferAmountUpdated(uint256 indexed id, Offer offer);

    event NFTOfferCanceled(uint256 indexed id, Offer offer);

    event NFTOfferFilled(uint256 indexed id, address indexed buyer, address indexed finder, Offer offer);

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

    /// @notice Places an offer on a NFT
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenId The ID of the ERC-721 token to place the offer
    /// @param _offerAmount The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created NFT offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerAmount,
        address _offerCurrency,
        uint8 _findersFeePercentage
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createNFTOffer cannot make offer on owned NFT");
        require(_findersFeePercentage <= 100, "createNFTOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerAmount, _offerCurrency);

        offerCounter.increment();
        uint256 offerId = offerCounter.current();

        offers[offerId] = Offer({
            active: true,
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            offerAmount: _offerAmount,
            findersFeePercentage: _findersFeePercentage
        });

        uint256 _index = offersForNFT[_tokenContract][_tokenId].length;

        offersForNFT[_tokenContract][_tokenId].push(offerId);
        offerToIndex[_tokenContract][_tokenId][offerId] = _index;

        emit NFTOfferCreated(offerId, offers[offerId]);

        return offerId;
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _newOffer The new offer price
    function setNFTOfferAmount(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.active, "setNFTOfferAmount must be active offer");
        require(offer.buyer == msg.sender, "setNFTOfferAmount must be buyer from original offer");

        uint256 prevOffer = offer.offerAmount;

        require((_newOffer > 0) && (_newOffer != prevOffer), "setNFTOfferAmount _newOffer must be greater than 0 and not equal to previous offer");

        if (_newOffer > prevOffer) {
            uint256 increaseAmount = _newOffer - prevOffer;

            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerAmount += increaseAmount;
        } else if (_newOffer < prevOffer) {
            uint256 decreaseAmount = prevOffer - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency, USE_ALL_GAS_FLAG);

            offer.offerAmount -= decreaseAmount;
        }

        emit NFTOfferAmountUpdated(_offerId, offer);
    }

    /// @notice Cancels a NFT offer
    /// @param _offerId The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.active, "cancelNFTOffer must be active offer");
        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer from original offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerAmount, offer.offerCurrency, USE_ALL_GAS_FLAG);

        emit NFTOfferCanceled(_offerId, offer);

        uint256 _index = offerToIndex[offer.tokenContract][offer.tokenId][_offerId];

        delete offersForNFT[offer.tokenContract][offer.tokenId][_index];
        delete offerToIndex[offer.tokenContract][offer.tokenId][_offerId];
        delete offers[_offerId];
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Fills a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTOffer(uint256 _offerId, address _finder) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.active, "fillNFTOffer must be active offer");
        require(_finder != address(0), "fillNFTOffer _finder must not be 0 address");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenId), "fillNFTOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(offer.tokenContract, offer.tokenId, offer.offerAmount, offer.offerCurrency, USE_ALL_GAS_FLAG);
        uint256 finderFee = (remainingProfit * offer.findersFeePercentage) / 100;

        _handleOutgoingTransfer(_finder, finderFee, offer.offerCurrency, USE_ALL_GAS_FLAG);

        remainingProfit = remainingProfit - finderFee;

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerAmount});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_offerId, offer.buyer, _finder, offer);

        uint256 _index = offerToIndex[offer.tokenContract][offer.tokenId][_offerId];

        delete offersForNFT[offer.tokenContract][offer.tokenId][_index];
        delete offerToIndex[offer.tokenContract][offer.tokenId][_offerId];
        delete offers[_offerId];
    }
}
