// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Covered Calls V2
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows sellers to place ERC20 covered call options on their NFTs
contract CoveredCallsV2 is ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata of a covered call option
    /// @param seller The address of the seller that created the call option
    /// @param buyer The address of the buyer, or address(0) if not purchased, that purchased the option
    /// @param currency The address of the ERC-20 denominating the strike and premium
    /// @param premium The premium price to purchase the call option
    /// @param strike The strike price to exercise the call option
    /// @param expiration The expiration time of the call option
    struct Call {
        address seller;
        address buyer;
        address currency;
        uint256 premium;
        uint256 strike;
        uint256 expiration;
    }

    /// ------------ STORAGE ------------

    /// @notice The covered call option for a given NFT, if one exists
    /// @dev ERC-721 token address => ERC-721 token ID => Call
    mapping(address => mapping(uint256 => Call)) public callForNFT;

    /// ------------ EVENTS ------------

    /// @notice Emitted when a covered call option is created
    /// @param tokenContract The ERC-721 token address of the created call option
    /// @param tokenId The ERC-721 token ID of the created call option
    event CallCreated(address tokenContract, uint256 tokenId);

    /// @notice Emitted when a covered call option is canceled
    /// @param tokenContract The ERC-721 token address of the canceled call option
    /// @param tokenId The ERC-721 token ID of the canceled call option
    event CallCanceled(address tokenContract, uint256 tokenId);

    /// @notice Emitted when the NFT from an expired call option is reclaimed
    /// @param tokenContract The ERC-721 token address of the reclaimed call option
    /// @param tokenId The ERC-721 token ID of the reclaimed call option
    event CallReclaimed(address tokenContract, uint256 tokenId);

    /// @notice Emitted when a covered call option is purchased
    /// @param tokenContract The ERC-721 token address of the purchased call option
    /// @param tokenId The ERC-721 token ID of the purchased call option
    /// @param buyer The address that purchased the call option
    event CallPurchased(address tokenContract, uint256 tokenId, address buyer);

    /// @notice Emitted when a covered call option is exercised
    /// @param tokenContract The ERC-721 token address of the exercised call option
    /// @param tokenId The ERC-721 token ID of the exercised call option
    event CallExercised(address tokenContract, uint256 tokenId);

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
        ModuleNamingSupportV1("Covered Calls: v2.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ SELLER FUNCTIONS ------------

    /// @notice Creates a covered call option for an NFT
    /// @param _tokenContract The address of the ERC-721 token to sell
    /// @param _tokenId The ID of the ERC-721 token to sell
    /// @param _premiumPrice The premium price to purchase the call option
    /// @param _strikePrice The strike price to exercise the call option
    /// @param _expiration The expiration time of the call option
    /// @param _currency The address of the ERC-20 to accept the strike and premium
    function createCall(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _premiumPrice,
        uint256 _strikePrice,
        uint256 _expiration,
        address _currency
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createCall must be token owner or operator"
        );
        require(erc721TransferHelper.isModuleApproved(msg.sender), "createCall must approve module");
        require(
            IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createCall must approve ERC721TransferHelper as operator"
        );
        require(_expiration > block.timestamp, "createCall _expiration must be future time");

        if (callForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelCall(_tokenContract, _tokenId);
        }

        callForNFT[_tokenContract][_tokenId] = Call({
            seller: tokenOwner,
            buyer: address(0),
            currency: _currency,
            premium: _premiumPrice,
            strike: _strikePrice,
            expiration: _expiration
        });

        emit CallCreated(_tokenContract, _tokenId);
    }

    /// @notice Cancels a non-purchased call option for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function cancelCall(address _tokenContract, uint256 _tokenId) external {
        Call memory call = callForNFT[_tokenContract][_tokenId];

        require(call.seller != address(0), "cancelCall call does not exist");
        require(call.buyer == address(0), "cancelCall call has been purchased");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "cancelCall must be seller or invalid call"
        );

        _cancelCall(_tokenContract, _tokenId);
    }

    /// @notice Returns the NFT from a purchased, but non-exercised call option
    /// @param _tokenContract The address of the ERC-721 token to reclaim
    /// @param _tokenId The ID of the ERC-721 token to reclaim
    function reclaimCall(address _tokenContract, uint256 _tokenId) external nonReentrant {
        Call memory call = callForNFT[_tokenContract][_tokenId];

        require(msg.sender == call.seller, "reclaimCall must be seller");
        require(call.buyer != address(0), "reclaimCall call not purchased");
        require(block.timestamp >= call.expiration, "reclaimCall call is active");

        // Transfer NFT back to seller
        IERC721(_tokenContract).transferFrom(address(this), call.seller, _tokenId);

        emit CallReclaimed(_tokenContract, _tokenId);

        delete callForNFT[_tokenContract][_tokenId];
    }

    /// ------------ BUYER FUNCTIONS ------------

    /// @notice Purchases a call option -- transferring the NFT to the contract and premium to the seller
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ERC-721 token ID
    /// @param _currency The ERC-20 address of the strike and premium, or address(0) for ETH
    /// @param _premium The premium price to pay for the call option
    /// @param _strike The strike price to exercise the call option
    function buyCall(
        address _tokenContract,
        uint256 _tokenId,
        address _currency,
        uint256 _premium,
        uint256 _strike
    ) external payable nonReentrant {
        Call storage call = callForNFT[_tokenContract][_tokenId];

        require(call.seller != address(0), "buyCall call does not exist");
        require(call.buyer == address(0), "buyCall call already purchased");
        require(call.expiration > block.timestamp, "buyCall call expired");
        require(call.currency == _currency, "buyCall _currency must match call");
        require(call.premium == _premium, "buyCall _premium must match call");
        require(call.strike == _strike, "buyCall _strike must match call");

        // Ensure premium payment is valid and take custody
        _handleIncomingTransfer(call.premium, call.currency);

        // Transfer NFT to escrow from seller
        erc721TransferHelper.transferFrom(_tokenContract, call.seller, address(this), _tokenId);

        // Transfer premium to seller
        _handleOutgoingTransfer(call.seller, call.premium, call.currency, 30000);

        // Mark option as purchased
        call.buyer = msg.sender;

        emit CallPurchased(_tokenContract, _tokenId, msg.sender);
    }

    /// @notice Exercises a call option -- transferring the NFT to the buyer and strike to the seller
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ERC-721 token ID
    function exerciseCall(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        Call memory call = callForNFT[_tokenContract][_tokenId];

        require(call.buyer == msg.sender, "exerciseCall must be buyer");
        require(call.expiration > block.timestamp, "exerciseCall call expired");

        // Ensure strike payment is valid and take custody
        _handleIncomingTransfer(call.strike, call.currency);

        // Payout respective parties, ensuring NFT royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, call.strike, call.currency, 75000);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, call.currency);

        // Transfer strike (post royalties) to seller
        _handleOutgoingTransfer(call.seller, remainingProfit, call.currency, 30000);

        // Transfer NFT to buyer
        IERC721(_tokenContract).transferFrom(address(this), msg.sender, _tokenId);

        emit CallExercised(_tokenContract, _tokenId);

        delete callForNFT[_tokenContract][_tokenId];
    }

    /// ------------ PRIVATE FUNCTIONS ------------

    /// @dev Deletes canceled and invalid call options
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function _cancelCall(address _tokenContract, uint256 _tokenId) private {
        emit CallCanceled(_tokenContract, _tokenId);

        delete callForNFT[_tokenContract][_tokenId];
    }
}
