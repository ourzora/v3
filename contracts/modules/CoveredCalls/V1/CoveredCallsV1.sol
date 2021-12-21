// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {RoyaltyPayoutSupportV1} from "../../../common/RoyaltyPayoutSupport/V1/RoyaltyPayoutSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";

/// @title CoveredCalls V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows users to sell covered call options on their NFTs
contract CoveredCallsV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, RoyaltyPayoutSupportV1 {
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    struct Call {
        address seller;
        address sellerFundsRecipient;
        address buyer;
        address currency;
        uint256 premium;
        uint256 strike;
        uint256 expiry;
    }

    /// ------------ PUBLIC STORAGE ------------

    /// @notice The call for a given NFT, if one exists
    /// @dev NFT address => NFT ID => Call
    mapping(address => mapping(uint256 => Call)) public callForNFT;

    /// ------------ EVENTS ------------

    event CallCreated(address indexed tokenContract, uint256 indexed tokenId, Call call);

    event CallPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Call call);

    event CallCanceled(address indexed tokenContract, uint256 indexed tokenId, Call call);

    event CallPurchased(address indexed tokenContract, uint256 indexed tokenId, address indexed buyer, Call call);

    event CallExercised(address indexed tokenContract, uint256 indexed tokenId, address indexed buyer, Call call);

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

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Creates a covered call on an NFT
    /// @param _tokenContract The address of the ERC-721 token contract for the token to be sold
    /// @param _tokenId The ERC-721 token ID for the token to be sold
    /// @param _premiumPrice The premium price for the call option
    /// @param _strikePrice The strike price for the call option
    /// @param _currency The currency to pay the strike and premium prices of the call option
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _expiry The time of expiration
    function createCall(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _premiumPrice,
        uint256 _strikePrice,
        address _currency,
        address _sellerFundsRecipient,
        uint256 _expiry
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createCall must be token owner or approved operator"
        );
        require(
            (IERC721(_tokenContract).getApproved(_tokenId) == address(erc721TransferHelper)) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createCall must approve ZORA ERC-721 Transfer Helper from _tokenContract"
        );

        if (callForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelCall(_tokenContract, _tokenId);
        }

        require(_sellerFundsRecipient != address(0), "createCall must specify sellerFundsRecipient");
        require(_expiry > block.timestamp, "createCall _expiry must be a future block");

        callForNFT[_tokenContract][_tokenId] = Call({
            seller: tokenOwner,
            sellerFundsRecipient: _sellerFundsRecipient,
            buyer: payable(address(0)),
            currency: _currency,
            premium: _premiumPrice,
            strike: _strikePrice,
            expiry: _expiry
        });

        emit CallCreated(_tokenContract, _tokenId, callForNFT[_tokenContract][_tokenId]);
    }

    /// @notice Cancels a call
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function cancelCall(address _tokenContract, uint256 _tokenId) external {
        require(callForNFT[_tokenContract][_tokenId].seller != address(0), "cancelCall call doesn't exist");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            (msg.sender == tokenOwner) ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) ||
                (msg.sender == IERC721(_tokenContract).getApproved(_tokenId)),
            "cancelCall must be seller or invalid call"
        );

        _cancelCall(_tokenContract, _tokenId);
    }

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Purchase an NFT call option, transferring the NFT to the buyer and funds to the recipients
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function buyCall(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        Call storage call = callForNFT[_tokenContract][_tokenId];

        require(call.seller != address(0), "buyCall must be active call");
        require(call.buyer == address(0), "buyCall call already purchased");
        require(call.expiry > block.timestamp, "buyCall call expired");

        // Ensure payment is valid and take custody of premium
        _handleIncomingTransfer(call.premium, call.currency);
        // Transfer premium to seller
        _handleOutgoingTransfer(call.seller, call.premium, call.currency, USE_ALL_GAS_FLAG);

        call.buyer = msg.sender;

        emit CallPurchased(_tokenContract, _tokenId, msg.sender, call);
    }

    /// @notice Exercises a call option, transferring the NFT to the buyer and funds to the recipients
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function exerciseCall(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        Call storage call = callForNFT[_tokenContract][_tokenId];

        require(call.buyer == msg.sender, "exerciseCall must be buyer");
        require(call.expiry > block.timestamp, "exerciseCall call expired");

        // Ensure payment is valid and take custody of premium
        _handleIncomingTransfer(call.strike, call.currency);

        // Payout respective parties, ensuring NFT royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, call.strike, call.currency, USE_ALL_GAS_FLAG);

        // Transfer strike to seller
        _handleOutgoingTransfer(call.sellerFundsRecipient, remainingProfit, call.currency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, call.seller, msg.sender, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: call.currency, tokenId: 0, amount: call.strike});

        emit ExchangeExecuted(call.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit CallExercised(_tokenContract, _tokenId, msg.sender, call);

        delete callForNFT[_tokenContract][_tokenId];
    }

    /// ------------ PRIVATE FUNCTIONS ------------

    /// @notice Removes a call
    /// @param _tokenContract The address of the ERC-721 token contract for the token
    /// @param _tokenId The ERC-721 token ID for the token
    function _cancelCall(address _tokenContract, uint256 _tokenId) private {
        emit CallCanceled(_tokenContract, _tokenId, callForNFT[_tokenContract][_tokenId]);

        delete callForNFT[_tokenContract][_tokenId];
    }
}
