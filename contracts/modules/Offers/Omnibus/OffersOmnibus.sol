// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

import {IOffersOmnibus} from "./IOffersOmnibus.sol";
import {OffersDataStorage} from "./OffersDataStorage.sol";

/// @title Offers Omnibus
/// @author jgeary
/// @notice Omnibus module for multi-featured offers for ERC-721 tokens
contract OffersOmnibus is IOffersOmnibus, ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1, OffersDataStorage {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice Emitted when an offer is created
    /// @param tokenContract The ERC-721 token address of the created offer
    /// @param tokenId The ERC-721 token ID of the created offer
    /// @param id The ID of the created offer
    /// @param offer The metadata of the created offer
    event OfferCreated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, FullOffer offer);

    /// @notice Emitted when an offer amount is updated
    /// @param tokenContract The ERC-721 token address of the updated offer
    /// @param tokenId The ERC-721 token ID of the updated offer
    /// @param id The ID of the updated offer
    /// @param offer The metadata of the updated offer
    event OfferUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, FullOffer offer);

    /// @notice Emitted when an offer is canceled
    /// @param tokenContract The ERC-721 token address of the canceled offer
    /// @param tokenId The ERC-721 token ID of the canceled offer
    /// @param id The ID of the canceled offer
    /// @param offer The metadata of the canceled offer
    event OfferCanceled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, FullOffer offer);

    /// @notice Emitted when an offer is filled
    /// @param tokenContract The ERC-721 token address of the filled offer
    /// @param tokenId The ERC-721 token ID of the filled offer
    /// @param id The ID of the filled offer
    /// @param taker The address of the taker who filled the offer
    /// @param finder The address of the finder who referred the offer
    /// @param offer The metadata of the filled offer
    event OfferFilled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, address taker, address finder, FullOffer offer);

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        IncomingTransferSupportV1(_erc20TransferHelper)
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Offers Omnibus")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IOffersOmnibus).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Creates a simple WETH offer for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function createOfferMinimal(address _tokenContract, uint256 _tokenId) external payable nonReentrant returns (uint256) {
        uint256 _offerAmount = msg.value;
        weth.deposit{value: msg.value}();
        weth.transferFrom(address(this), msg.sender, _offerAmount);

        if (weth.allowance(msg.sender, address(erc20TransferHelper)) < _offerAmount) revert INSUFFICIENT_ALLOWANCE();
        if (!erc721TransferHelper.isModuleApproved(msg.sender)) revert MODULE_NOT_APPROVED();

        ++offerCount;

        StoredOffer storage offer = offers[_tokenContract][_tokenId][offerCount];
        offer.amount = _offerAmount;
        offer.maker = msg.sender;
        offer.features = 0;

        offersForNFT[_tokenContract][_tokenId].push(offerCount);
        emit OfferCreated(_tokenContract, _tokenId, offerCount, _getFullOffer(offer));
        return offerCount;
    }

    /// @notice Creates an offer for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _offerAmount The amount of ERC20 token offered
    /// @param _offerCurrency Address of ERC20 token
    /// @param _expiry Timestamp after which the ask expires
    /// @param _findersFeeBps Finders fee basis points
    /// @param _listingFeeBps Listing fee basis points
    /// @param _listingFeeRecipient Listing fee recipient
    function createOffer(
        address _tokenContract,
        uint256 _tokenId,
        address _offerCurrency,
        uint256 _offerAmount,
        uint96 _expiry,
        uint16 _findersFeeBps,
        uint16 _listingFeeBps,
        address _listingFeeRecipient
    ) external payable nonReentrant returns (uint256) {
        if (_offerAmount == 0) revert NO_ZERO_OFFERS();

        ++offerCount;
        offersForNFT[_tokenContract][_tokenId].push(offerCount);
        StoredOffer storage offer = offers[_tokenContract][_tokenId][offerCount];

        if (_offerCurrency != address(0)) {
            if (msg.value > 0) revert MSG_VALUE_NEQ_ZERO_WITH_OTHER_CURRENCY();
            IERC20 token = IERC20(_offerCurrency);
            if (token.balanceOf(msg.sender) < _offerAmount) revert INSUFFICIENT_BALANCE();
            if (token.allowance(msg.sender, address(erc20TransferHelper)) < _offerAmount) revert INSUFFICIENT_ALLOWANCE();
        } else {
            if (msg.value != _offerAmount) revert MSG_VALUE_NEQ_OFFER_AMOUNT();
            weth.deposit{value: msg.value}();
            weth.transferFrom(address(this), msg.sender, _offerAmount);
            if (weth.balanceOf(msg.sender) < _offerAmount) revert INSUFFICIENT_BALANCE();
            if (weth.allowance(msg.sender, address(erc20TransferHelper)) < _offerAmount) revert INSUFFICIENT_ALLOWANCE();
        }
        if (!erc721TransferHelper.isModuleApproved(msg.sender)) revert MODULE_NOT_APPROVED();

        offer.maker = msg.sender;
        offer.amount = _offerAmount;
        offer.features = 0;

        _setETHorERC20Currency(offer, _offerCurrency);

        if (_findersFeeBps + _listingFeeBps > 10000) revert INVALID_FEES();

        if (_listingFeeBps > 0) {
            _setListingFee(offer, _listingFeeBps, _listingFeeRecipient);
        }

        if (_findersFeeBps > 0) {
            _setFindersFee(offer, _findersFeeBps);
        }

        if (_expiry > 0) {
            if (_expiry < block.timestamp) revert INVALID_EXPIRY();
            _setExpiry(offer, _expiry);
        }

        emit OfferCreated(_tokenContract, _tokenId, offerCount, _getFullOffer(offer));
        return offerCount;
    }

    /// @notice Updates the price of the given offer
    /// @param _tokenContract The address of the offer ERC-721 token
    /// @param _tokenId The ID of the offer ERC-721 token
    /// @param _offerId The ID of the offer
    /// @param _offerCurrency The address of the ERC-20 token offered
    /// @param _offerAmount The new amount offered
    function setOfferAmount(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _offerCurrency,
        uint256 _offerAmount
    ) external payable nonReentrant {
        StoredOffer storage offer = offers[_tokenContract][_tokenId][_offerId];

        if (offer.maker != msg.sender) revert CALLER_NOT_MAKER();

        if (_offerAmount == 0) revert NO_ZERO_OFFERS();
        if (_offerAmount == offer.amount && _offerCurrency == _getERC20CurrencyWithFallback(offer)) revert SAME_OFFER();

        IERC20 token = IERC20(address(weth));
        if (_offerCurrency != address(0)) {
            if (msg.value != 0) revert MSG_VALUE_NEQ_ZERO_WITH_OTHER_CURRENCY();
            token = IERC20(_offerCurrency);
        }
        if (_offerCurrency == address(0) && msg.value > 0) {
            weth.deposit{value: msg.value}();
            weth.transferFrom(address(this), msg.sender, msg.value);
        }
        if (token.balanceOf(msg.sender) < _offerAmount) revert INSUFFICIENT_BALANCE();
        if (token.allowance(msg.sender, address(erc20TransferHelper)) < _offerAmount) revert INSUFFICIENT_ALLOWANCE();

        _setETHorERC20Currency(offer, _offerCurrency);
        offer.amount = _offerAmount;

        emit OfferUpdated(_tokenContract, _tokenId, _offerId, _getFullOffer(offer));
    }

    /// @notice Cancels the given offer for an NFT
    /// @param _tokenContract The ERC-721 token address of the offer
    /// @param _tokenId The ERC-721 token ID of the offer
    /// @param _offerId The ID of the offer
    function cancelOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external nonReentrant {
        if (offers[_tokenContract][_tokenId][_offerId].maker != msg.sender) revert CALLER_NOT_MAKER();

        emit OfferCanceled(_tokenContract, _tokenId, _offerId, _getFullOffer(offers[_tokenContract][_tokenId][_offerId]));

        // Remove the offer from storage
        delete offers[_tokenContract][_tokenId][_offerId];
    }

    function _handleListingAndFindersFees(
        uint256 _remainingProfit,
        StoredOffer storage offer,
        address _currency,
        address _finder
    ) internal returns (uint256 remainingProfit) {
        remainingProfit = _remainingProfit;
        uint256 listingFee;
        address listingFeeRecipient;
        uint256 findersFee;

        if (_hasFeature(offer.features, FEATURE_MASK_LISTING_FEE)) {
            uint16 listingFeeBps;
            (listingFeeBps, listingFeeRecipient) = _getListingFee(offer);
            listingFee = (remainingProfit * listingFeeBps) / 10000;
        }

        if (_finder != address(0) && _hasFeature(offer.features, FEATURE_MASK_FINDERS_FEE)) {
            findersFee = (remainingProfit * _getFindersFee(offer)) / 10000;
        }

        if (listingFee > 0) {
            _handleOutgoingTransfer(listingFeeRecipient, listingFee, _currency, 50000);
            remainingProfit -= listingFee;
        }
        if (findersFee > 0) {
            _handleOutgoingTransfer(_finder, findersFee, _currency, 50000);
            remainingProfit -= findersFee;
        }
    }

    /// @notice Fills an offer for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _offerId The id of the offer
    /// @param _amount The offer amount
    /// @param _currency The offer currency
    /// @param _finder The offer finder
    function fillOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        uint256 _amount,
        address _currency,
        address _finder
    ) external nonReentrant {
        StoredOffer storage offer = offers[_tokenContract][_tokenId][_offerId];

        if (offer.maker == address(0)) revert INACTIVE_OFFER();
        if (IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender) revert NOT_TOKEN_OWNER();
        address incomingTransferCurrency = _getERC20CurrencyWithFallback(offer);

        if (incomingTransferCurrency != _currency || offer.amount != _amount) revert INCORRECT_CURRENCY_OR_AMOUNT();
        if (_currency == address(0)) {
            incomingTransferCurrency = address(weth);
        }
        IERC20 token = IERC20(incomingTransferCurrency);
        uint256 beforeBalance = token.balanceOf(address(this));
        erc20TransferHelper.safeTransferFrom(incomingTransferCurrency, offer.maker, address(this), _amount);
        uint256 afterBalance = token.balanceOf(address(this));
        if (beforeBalance + _amount != afterBalance) revert TOKEN_TRANSFER_AMOUNT_INCORRECT();
        if (_currency == address(0)) {
            weth.withdraw(_amount);
        }

        if (_hasFeature(offer.features, FEATURE_MASK_EXPIRY)) {
            if (_getExpiry(offer) < block.timestamp) revert OFFER_EXPIRED();
        }

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, _amount, _currency, 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, _currency);

        remainingProfit = _handleListingAndFindersFees(remainingProfit, offer, _currency, _finder);

        // Transfer the remaining profit to the filler
        _handleOutgoingTransfer(msg.sender, remainingProfit, _currency, 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.maker, _tokenId);

        emit OfferFilled(_tokenContract, _tokenId, _offerId, msg.sender, _finder, _getFullOffer(offer));

        // Remove the ask from storage
        delete offers[_tokenContract][_tokenId][_offerId];
    }

    function getFullOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external view returns (FullOffer memory) {
        return _getFullOffer(offers[_tokenContract][_tokenId][_offerId]);
    }

    // This fallback is necessary so the module can call weth.withdraw
    fallback() external payable {
        require(msg.sender == address(weth));
    }
}
