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

    ERC721TransferHelper public immutable erc721TransferHelper;

    Counters.Counter public nftOfferCounter;

    /// @notice The NFT offers created by a given user
    /// @dev User address => NFT offer ID
    mapping(address => uint256[]) public nftOffersPerUser;

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// @notice A mapping of IDs to their respective NFT offer
    mapping(uint256 => NFTOffer) public nftOffers;

    enum OfferStatus {
        Active,
        Canceled,
        Filled
    }

    struct NFTOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 tokenId;
        uint256 offerAmount;
        uint8 findersFeePercentage;
        OfferStatus status;
    }

    event NFTOfferCreated(uint256 indexed id, NFTOffer offer);

    event NFTOfferAmountUpdated(uint256 indexed id, NFTOffer offer);

    event NFTOfferCanceled(uint256 indexed id, NFTOffer offer);

    event NFTOfferFilled(uint256 indexed id, address indexed buyer, address indexed finder, NFTOffer offer);

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
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createNFTOffer cannot make offer on NFT you own");
        require(_findersFeePercentage <= 100, "createNFTOffer finders fee percentage must be less than 100");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerAmount, _offerCurrency);

        nftOfferCounter.increment();
        uint256 offerId = nftOfferCounter.current();

        nftOffers[offerId] = NFTOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            offerAmount: _offerAmount,
            findersFeePercentage: _findersFeePercentage,
            status: OfferStatus.Active
        });

        nftOffersPerUser[msg.sender].push(offerId);
        offersForNFT[_tokenContract][_tokenId].push(offerId);

        emit NFTOfferCreated(offerId, nftOffers[offerId]);

        return offerId;
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _newOffer The new offer price
    function setNFTOfferAmount(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.buyer == msg.sender, "setNFTOfferAmount must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "setNFTOfferAmount must be active offer");

        if (_newOffer > offer.offerAmount) {
            uint256 increaseAmount = _newOffer - offer.offerAmount;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerAmount += increaseAmount;

            emit NFTOfferAmountUpdated(_offerId, offer);
        } else if (_newOffer < offer.offerAmount) {
            uint256 decreaseAmount = offer.offerAmount - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency, USE_ALL_GAS_FLAG);
            offer.offerAmount -= decreaseAmount;

            emit NFTOfferAmountUpdated(_offerId, offer);
        }
    }

    /// @notice Cancels a NFT offer
    /// @param _offerId The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerId) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelNFTOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerAmount, offer.offerCurrency, USE_ALL_GAS_FLAG);

        offer.status = OfferStatus.Canceled;

        emit NFTOfferCanceled(_offerId, offer);
    }

    /// @notice Fills a NFT offer
    /// @param _offerId The ID of the NFT offer
    /// @param _finder The address of the referrer for this offer
    function fillNFTOffer(uint256 _offerId, address _finder) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerId];

        require(offer.status == OfferStatus.Active, "fillNFTOffer must be active offer");
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

        offer.status = OfferStatus.Filled;

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.tokenContract, tokenId: offer.tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: offer.offerCurrency, tokenId: 0, amount: offer.offerAmount});

        emit ExchangeExecuted(msg.sender, offer.buyer, userAExchangeDetails, userBExchangeDetails);
        emit NFTOfferFilled(_offerId, offer.buyer, _finder, offer);
    }
}
