// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

import {IAsksOmnibus} from "./IAsksOmnibus.sol";
import {AsksDataStorage} from "./AsksDataStorage.sol";

/// @title Asks
/// @author jgeary
/// @notice Omnibus module for multi-featured asks for ERC-721 tokens
contract AsksOmnibus is IAsksOmnibus, ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1, AsksDataStorage {
    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice Emitted when an ask is created
    /// @param tokenContract The ERC-721 token address of the created ask
    /// @param tokenId The ERC-721 token ID of the created ask
    /// @param ask The metadata of the created ask
    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, FullAsk ask);

    /// @notice Emitted when an ask price is updated
    /// @param tokenContract The ERC-721 token address of the updated ask
    /// @param tokenId The ERC-721 token ID of the updated ask
    /// @param ask The metadata of the updated ask
    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, FullAsk ask);

    /// @notice Emitted when an ask is canceled
    /// @param tokenContract The ERC-721 token address of the canceled ask
    /// @param tokenId The ERC-721 token ID of the canceled ask
    /// @param ask The metadata of the canceled ask
    event AskCanceled(address indexed tokenContract, uint256 indexed tokenId, FullAsk ask);

    /// @notice Emitted when an ask is filled
    /// @param tokenContract The ERC-721 token address of the filled ask
    /// @param tokenId The ERC-721 token ID of the filled ask
    /// @param buyer The buyer address of the filled ask
    /// @param finder The address of finder who referred the ask
    /// @param ask The metadata of the filled ask
    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, address indexed buyer, address finder, FullAsk ask);

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
        ModuleNamingSupportV1("Asks Omnibus: ERC20 / Finders Fee / Listing Fee / Expiry / Private / Token Gate")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IAsksOmnibus).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    /// @notice Creates a simple ETH ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _askPrice The ETH price to fill the ask
    function createAskMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        if (msg.sender != tokenOwner && !IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender)) revert NOT_TOKEN_OWNER_OR_OPERATOR();

        if (!erc721TransferHelper.isModuleApproved(msg.sender)) revert MODULE_NOT_APPROVED();
        if (!IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper))) revert TRANSFER_HELPER_NOT_APPROVED();

        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];
        ask.features = 0;
        ask.seller = tokenOwner;
        ask.price = _askPrice;

        emit AskCreated(_tokenContract, _tokenId, _getFullAsk(ask));
    }

    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _expiry Timestamp after which the ask expires
    /// @param _askPrice The price to fill the ask
    /// @param _sellerFundsRecipient Address that receives funds for seller
    /// @param _askCurrency Address of ERC20 token (or 0x0 for ETH)
    /// @param _buyer Specifid buyer for private asks
    /// @param _findersFeeBps Finders fee basis points
    /// @param _listingFeeBps Listing fee basis points
    /// @param _listingFeeRecipient Listing fee recipient
    /// @param _tokenGateToken Token gate erc20 token
    /// @param _tokenGateMinAmount Token gate bidder minimum amount
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint96 _expiry,
        uint256 _askPrice,
        address _sellerFundsRecipient,
        address _askCurrency,
        address _buyer,
        uint16 _findersFeeBps,
        uint16 _listingFeeBps,
        address _listingFeeRecipient,
        address _tokenGateToken,
        uint256 _tokenGateMinAmount
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        if (msg.sender != tokenOwner && !IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender)) revert NOT_TOKEN_OWNER_OR_OPERATOR();
        if (!erc721TransferHelper.isModuleApproved(msg.sender)) revert MODULE_NOT_APPROVED();
        if (!IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper))) revert TRANSFER_HELPER_NOT_APPROVED();

        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];

        ask.features = 0;

        if ((_listingFeeBps > 0 && _listingFeeRecipient == address(0)) || (_listingFeeBps == 0 && _listingFeeRecipient != address(0)))
            revert INVALID_LISTING_FEE();
        if (_listingFeeBps + _findersFeeBps > 10000) revert INVALID_FEES();

        if (_listingFeeBps > 0) {
            _setListingFee(ask, _listingFeeBps, _listingFeeRecipient);
        }

        if (_findersFeeBps > 0) {
            _setFindersFee(ask, _findersFeeBps);
        }

        if ((_tokenGateMinAmount > 0 && _tokenGateToken == address(0)) || (_tokenGateMinAmount == 0 && _tokenGateToken != address(0)))
            revert INVALID_TOKEN_GATE();

        if (_tokenGateToken != address(0)) {
            _setTokenGate(ask, _tokenGateToken, _tokenGateMinAmount);
        }

        if (_expiry > 0 || (_sellerFundsRecipient != address(0) && _sellerFundsRecipient != tokenOwner)) {
            if (_expiry != 0 && _expiry <= block.timestamp) revert INVALID_EXPIRY();
            _setExpiryAndFundsRecipient(ask, _expiry, _sellerFundsRecipient);
        }

        if (_askCurrency != address(0)) {
            _setERC20Currency(ask, _askCurrency);
        }

        if (_buyer != address(0)) {
            _setBuyer(ask, _buyer);
        }

        ask.seller = tokenOwner;
        ask.price = _askPrice;

        emit AskCreated(_tokenContract, _tokenId, _getFullAsk(ask));
    }

    /// @notice Updates the price of a given NFT's live ask
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _askPrice The price to fill the ask
    /// @param _askCurrency Address of ERC20 token (or 0x0 for ETH)
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency
    ) external nonReentrant {
        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];

        if (msg.sender != ask.seller && !IERC721(_tokenContract).isApprovedForAll(ask.seller, msg.sender)) {
            revert NOT_TOKEN_OWNER_OR_OPERATOR();
        }

        ask.price = _askPrice;

        _setETHorERC20Currency(ask, _askCurrency);

        emit AskPriceUpdated(_tokenContract, _tokenId, _getFullAsk(ask));
    }

    /// @notice Cancels an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the ask for the specified token
        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];

        // If token is still owned by seller, only seller or operator can cancel (otherwise public)
        if (
            IERC721(_tokenContract).ownerOf(_tokenId) == ask.seller &&
            msg.sender != ask.seller &&
            !IERC721(_tokenContract).isApprovedForAll(ask.seller, msg.sender)
        ) {
            revert NOT_TOKEN_OWNER_OR_OPERATOR();
        }

        emit AskCanceled(_tokenContract, _tokenId, _getFullAsk(ask));

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }

    function _handleListingAndFindersFees(
        uint256 _remainingProfit,
        StoredAsk storage ask,
        address currency,
        address finder
    ) internal returns (uint256 remainingProfit) {
        remainingProfit = _remainingProfit;
        uint256 listingFee;
        address listingFeeRecipient;
        uint256 findersFee;

        if (_hasFeature(ask.features, FEATURE_MASK_LISTING_FEE)) {
            uint16 listingFeeBps;
            (listingFeeBps, listingFeeRecipient) = _getListingFee(ask);
            listingFee = (remainingProfit * listingFeeBps) / 10000;
        }

        if (finder != address(0) && _hasFeature(ask.features, FEATURE_MASK_FINDERS_FEE)) {
            findersFee = (remainingProfit * _getFindersFee(ask)) / 10000;
        }

        if (listingFee > 0) {
            _handleOutgoingTransfer(listingFeeRecipient, listingFee, currency, 50000);
            remainingProfit -= listingFee;
        }
        if (findersFee > 0) {
            _handleOutgoingTransfer(finder, findersFee, currency, 50000);
            remainingProfit -= findersFee;
        }
    }

    /// @notice Fills an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The ask price
    /// @param _currency The ask currency
    /// @param _finder The ask finder
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency,
        address _finder
    ) external payable nonReentrant {
        // Get the ask for the specified token
        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = ask.seller;

        // Ensure the ask is active
        if (seller == address(0)) revert ASK_INACTIVE();

        // Cache the price
        uint256 price = ask.price;
        address currency = _getERC20CurrencyWithFallback(ask);

        // Ensure the specified price matches the ask price
        if (_price != price || _currency != currency) revert INCORRECT_CURRENCY_OR_AMOUNT();

        address fundsRecipient = ask.seller;

        if (_hasFeature(ask.features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
            (uint96 expiry, address storedFundsRecipient) = _getExpiryAndFundsRecipient(ask);
            if (storedFundsRecipient != address(0)) {
                fundsRecipient = storedFundsRecipient;
            }
            if (expiry < block.timestamp) revert ASK_EXPIRED();
        }

        if (_hasFeature(ask.features, FEATURE_MASK_TOKEN_GATE)) {
            (address tokenGateToken, uint256 tokenGateMinAmount) = _getAskTokenGate(ask);
            if (IERC20(tokenGateToken).balanceOf(msg.sender) < tokenGateMinAmount) revert TOKEN_GATE_INSUFFICIENT_BALANCE();
        }

        if (_hasFeature(ask.features, FEATURE_MASK_BUYER)) {
            if (msg.sender != _getBuyerWithFallback(ask)) revert NOT_DESIGNATED_BUYER();
        }

        // Transfer the ask price from the buyer
        // If ETH, this reverts if the buyer did not attach enough
        // If ERC-20, this reverts if the buyer did not approve the ERC20TransferHelper or does not own the specified tokens
        _handleIncomingTransfer(price, currency);

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, price, currency, 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, currency);

        remainingProfit = _handleListingAndFindersFees(remainingProfit, ask, currency, _finder);

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(fundsRecipient, remainingProfit, currency, 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, seller, msg.sender, _tokenId);

        emit AskFilled(_tokenContract, _tokenId, msg.sender, _finder, _getFullAsk(ask));

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }

    function getFullAsk(address _tokenContract, uint256 _tokenId) external view returns (FullAsk memory) {
        StoredAsk storage ask = askForNFT[_tokenContract][_tokenId];
        return _getFullAsk(ask);
    }
}
