// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title Asks V1
/// @author tbtstl <t@zora.co>
/// @notice This module allows sellers to list an owned ERC-721 token for sale for a given price in a given currency, and allows buyers to purchase from those asks
contract AsksV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeMath for uint8;

    uint256 private constant USE_ALL_GAS_FLAG = 0;

    ERC721TransferHelper public immutable erc721TransferHelper;

    Counters.Counter public askCounter;

    /// @notice The ask for a given NFT, if one exists
    /// @dev NFT address => NFT ID => ask ID
    mapping(address => mapping(uint256 => uint256)) public askForNFT;

    /// @notice A mapping of IDs to their respective ask
    mapping(uint256 => Ask) public asks;

    struct Ask {
        address tokenContract;
        address seller;
        address sellerFundsRecipient;
        address askCurrency;
        address listingFeeRecipient;
        uint256 tokenId;
        uint256 askPrice;
        uint8 listingFeePercentage;
        uint8 findersFeePercentage;
    }

    event AskCreated(uint256 indexed id, Ask ask);

    event AskPriceUpdated(uint256 indexed id, Ask ask);

    event AskCanceled(uint256 indexed id, Ask ask);

    event AskFilled(uint256 indexed id, address indexed buyer, address indexed finder, Ask ask);

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

    /// @notice Lists an NFT for sale
    /// @param _tokenContract The address of the ERC-721 token contract for the token to be sold
    /// @param _tokenId The ERC-721 token ID for the token to be sold
    /// @param _askPrice The price of the sale
    /// @param _askCurrency The address of the ERC-20 token to accept an offer in, or address(0) for ETH
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _listingFeeRecipient The listingFeeRecipient of the sale, who can receive _listingFeePercentage of the sale price
    /// @param _listingFeePercentage The percentage of the sale amount to be sent to the listingFeeRecipient
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @return The ID of the created ask
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency,
        address _sellerFundsRecipient,
        address _listingFeeRecipient,
        uint8 _listingFeePercentage,
        uint8 _findersFeePercentage
    ) external nonReentrant returns (uint256) {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        bool isOperatorForTokenOwner = IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender);
        bool isApprovedForToken = IERC721(_tokenContract).getApproved(_tokenId) == msg.sender;

        require((msg.sender == tokenOwner) || isOperatorForTokenOwner || isApprovedForToken, "createAsk must be token owner or approved operator");

        if (askForNFT[_tokenContract][_tokenId] != 0) {
            cancelAsk(askForNFT[_tokenContract][_tokenId]);
        }

        require(_sellerFundsRecipient != address(0), "createAsk must specify sellerFundsRecipient");
        require(_listingFeePercentage.add(_findersFeePercentage) <= 100, "createAsk listing fee and finders fee percentage must be less than 100");

        // Create an ask
        askCounter.increment();
        uint256 askId = askCounter.current();

        asks[askId] = Ask({
            tokenContract: _tokenContract,
            seller: msg.sender,
            sellerFundsRecipient: _sellerFundsRecipient,
            askCurrency: _askCurrency,
            listingFeeRecipient: _listingFeeRecipient,
            tokenId: _tokenId,
            askPrice: _askPrice,
            listingFeePercentage: _listingFeePercentage,
            findersFeePercentage: _findersFeePercentage
        });

        askForNFT[_tokenContract][_tokenId] = askId;

        emit AskCreated(askId, asks[askId]);

        return askId;
    }

    /// @notice Updates the ask price for a given ask
    /// @param _askId the ID of the ask to update
    /// @param _askPrice the price to update the ask to
    /// @param _askCurrency The address of the ERC-20 token to accept an offer in, or address(0) for ETH
    function setAskPrice(
        uint256 _askId,
        uint256 _askPrice,
        address _askCurrency
    ) external {
        Ask storage ask = asks[_askId];

        require(_askId == askForNFT[ask.tokenContract][ask.tokenId], "setAskPrice must be active ask");
        require(ask.seller == msg.sender, "setAskPrice must be seller");

        ask.askPrice = _askPrice;
        ask.askCurrency = _askCurrency;

        emit AskPriceUpdated(_askId, ask);
    }

    /// @notice Cancels a ask
    /// @param _askId the ID of the ask to cancel
    function cancelAsk(uint256 _askId) public {
        Ask storage ask = asks[_askId];

        require(_askId == askForNFT[ask.tokenContract][ask.tokenId], "cancelAsk must be active ask");

        address tokenOwner = IERC721(ask.tokenContract).ownerOf(ask.tokenId);
        bool isTokenOwner = tokenOwner == msg.sender;
        bool isOperatorForTokenOwner = IERC721(ask.tokenContract).isApprovedForAll(tokenOwner, msg.sender);
        bool isApprovedForToken = IERC721(ask.tokenContract).getApproved(ask.tokenId) == msg.sender;

        require((msg.sender == ask.seller) || isTokenOwner || isOperatorForTokenOwner || isApprovedForToken, "cancelAsk must be seller or invalid ask");

        emit AskCanceled(_askId, ask);

        delete askForNFT[ask.tokenContract][ask.tokenId];
        delete asks[_askId];
    }

    /// @notice Purchase an NFT from a ask, transferring the NFT to the buyer and funds to the recipients
    /// @param _askId The ID of the ask
    /// @param _finder The address of the referrer for this ask
    function fillAsk(uint256 _askId, address _finder) external payable nonReentrant {
        Ask storage ask = asks[_askId];

        require(_askId == askForNFT[ask.tokenContract][ask.tokenId], "fillAsk must be active ask");
        require(_finder != address(0), "fillAsk _finder must not be 0 address");

        // Ensure payment is valid and take custody of payment
        _handleIncomingTransfer(ask.askPrice, ask.askCurrency);

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(ask.tokenContract, ask.tokenId, ask.askPrice, ask.askCurrency, USE_ALL_GAS_FLAG);
        uint256 listingFeeRecipientProfit = remainingProfit.mul(ask.listingFeePercentage).div(100);
        uint256 finderFee = remainingProfit.mul(ask.findersFeePercentage).div(100);

        _handleOutgoingTransfer(ask.listingFeeRecipient, listingFeeRecipientProfit, ask.askCurrency, USE_ALL_GAS_FLAG);
        _handleOutgoingTransfer(_finder, finderFee, ask.askCurrency, USE_ALL_GAS_FLAG);

        remainingProfit = remainingProfit.sub(listingFeeRecipientProfit).sub(finderFee);

        _handleOutgoingTransfer(ask.sellerFundsRecipient, remainingProfit, ask.askCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(ask.tokenContract, ask.seller, msg.sender, ask.tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: ask.tokenContract, tokenId: ask.tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: ask.askCurrency, tokenId: 0, amount: ask.askPrice});

        emit ExchangeExecuted(ask.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit AskFilled(_askId, msg.sender, _finder, ask);

        delete askForNFT[ask.tokenContract][ask.tokenId];
        delete asks[_askId];
    }
}
