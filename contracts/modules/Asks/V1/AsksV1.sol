// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title Asks V1
/// @author tbtstl <t@zora.co>
/// @notice This module allows sellers to list an owned ERC-721 token for sale for a given price in a given currency, and allows buyers to purchase from those asks
contract AsksV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The ask for a given NFT, if one exists
    /// @dev NFT address => NFT ID => ask ID
    mapping(address => mapping(uint256 => Ask)) public askForNFT;

    struct Ask {
        address seller;
        address sellerFundsRecipient;
        address askCurrency;
        uint256 askPrice;
        uint256 findersFeePercentage;
    }

    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    event AskCanceled(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, address indexed buyer, address finder, Ask ask);

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
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency,
        address _sellerFundsRecipient,
        uint256 _findersFeePercentage
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAsk must be token owner or approved operator"
        );
        require(
            (IERC721(_tokenContract).getApproved(_tokenId) == address(erc721TransferHelper)) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createAsk must approve ZORA ERC-721 Transfer Helper from _tokenContract"
        );

        if (askForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelAsk(_tokenContract, _tokenId);
        }

        require(_sellerFundsRecipient != address(0), "createAsk must specify sellerFundsRecipient");
        require(_findersFeePercentage <= 100, "createAsk finders fee percentage must be less than or equal to 100");

        // Create an ask
        askForNFT[_tokenContract][_tokenId] = Ask({
            seller: tokenOwner,
            sellerFundsRecipient: _sellerFundsRecipient,
            askCurrency: _askCurrency,
            askPrice: _askPrice,
            findersFeePercentage: _findersFeePercentage
        });

        emit AskCreated(_tokenContract, _tokenId, askForNFT[_tokenContract][_tokenId]);
    }

    /// @notice Updates the ask price for a given ask
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    /// @param _askPrice the price to update the ask to
    /// @param _askCurrency The address of the ERC-20 token to accept an offer in, or address(0) for ETH
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency
    ) external {
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        require(ask.seller == msg.sender, "setAskPrice must be seller");

        ask.askPrice = _askPrice;
        ask.askCurrency = _askCurrency;

        emit AskPriceUpdated(_tokenContract, _tokenId, ask);
    }

    /// @notice Cancels a ask
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external {
        require(askForNFT[_tokenContract][_tokenId].seller != address(0), "cancelAsk ask doesn't exist");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) ||
                (msg.sender == IERC721(_tokenContract).getApproved(_tokenId)),
            "cancelAsk must be seller or invalid ask"
        );

        _cancelAsk(_tokenContract, _tokenId);
    }

    /// @notice Purchase an NFT from a ask, transferring the NFT to the buyer and funds to the recipients
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    /// @param _finder The address of the referrer for this ask
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        address _finder
    ) external payable nonReentrant {
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        require(ask.seller != address(0), "fillAsk must be active ask");

        // Ensure payment is valid and take custody of payment
        _handleIncomingTransfer(ask.askPrice, ask.askCurrency);

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, ask.askPrice, ask.askCurrency, USE_ALL_GAS_FLAG);

        if (_finder != address(0)) {
            uint256 finderFee = (remainingProfit * ask.findersFeePercentage) / 100;
            _handleOutgoingTransfer(_finder, finderFee, ask.askCurrency, USE_ALL_GAS_FLAG);

            remainingProfit = remainingProfit - finderFee;
        }

        _handleOutgoingTransfer(ask.sellerFundsRecipient, remainingProfit, ask.askCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, ask.seller, msg.sender, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: ask.askCurrency, tokenId: 0, amount: ask.askPrice});

        emit ExchangeExecuted(ask.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit AskFilled(_tokenContract, _tokenId, msg.sender, _finder, ask);

        delete askForNFT[_tokenContract][_tokenId];
    }

    /// @notice Removes an ask
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function _cancelAsk(address _tokenContract, uint256 _tokenId) private {
        emit AskCanceled(_tokenContract, _tokenId, askForNFT[_tokenContract][_tokenId]);

        delete askForNFT[_tokenContract][_tokenId];
    }
}
