// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Covered Calls ETH
/// @author kulkarohan
/// @notice Module for minimal ETH covered call options for ERC-721 tokens
contract CoveredCallsEth is ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                        MODULE SETUP                      ///
    ///                                                          ///

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    constructor(
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Covered Calls ETH")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    ///                                                          ///
    ///                        CALL STORAGE                      ///
    ///                                                          ///

    /// @notice The metadata for a covered call option
    /// @param seller The address of the seller
    /// @param premium The price to purchase the option
    /// @param buyer The address of the buyer, or address(0) if not yet purchased
    /// @param strike The price to exercise the option
    /// @param expiry The expiration time of the option
    struct Call {
        address seller;
        uint96 premium;
        address buyer;
        uint96 strike;
        uint256 expiry;
    }

    /// @notice The covered call option for a given NFT
    /// @dev ERC-721 token address => ERC-721 token id
    mapping(address => mapping(uint256 => Call)) public callForNFT;

    ///                                                          ///
    ///                        CREATE CALL                       ///
    ///                                                          ///

    /// @notice Emitted when a covered call option is created
    /// @param tokenContract The ERC-721 token address of the created call option
    /// @param tokenId The ERC-721 token id of the created call option
    event CallCreated(address tokenContract, uint256 tokenId, Call call);

    /// @notice Creates a covered call option for an NFT
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _premium The purchase price
    /// @param _strike The exercise price
    /// @param _expiry The expiration time
    function createCall(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _premium,
        uint256 _strike,
        uint256 _expiry
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        // Used to store the option metadata
        Call storage call = callForNFT[_tokenContract][_tokenId];

        // Store the token owner as the seller
        call.seller = tokenOwner;

        // Store the specified premium
        // This holds a max value greater than the total supply of ETH
        call.premium = uint96(_premium);

        // Store the specified strike
        // Peep 4 lines above
        call.strike = uint96(_strike);

        // Store the specified expiration
        call.expiry = _expiry;

        emit CallCreated(_tokenContract, _tokenId, call);
    }

    ///                                                          ///
    ///                        CANCEL CALL                       ///
    ///                                                          ///

    /// @notice Emitted when a covered call option is canceled
    /// @param tokenContract The ERC-721 token address of the canceled call option
    /// @param tokenId The ERC-721 token id of the canceled call option
    /// @param call The metadata of the canceled call option
    event CallCanceled(address tokenContract, uint256 tokenId, Call call);

    /// @notice Cancels a call option that has not yet been purchased
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    function cancelCall(address _tokenContract, uint256 _tokenId) external {
        // Get the option for the specified token
        Call memory call = callForNFT[_tokenContract][_tokenId];

        // Ensure the option has not been purchased
        require(call.buyer == address(0), "PURCHASED");

        // Ensure the caller is the seller or a new token owner
        require(msg.sender == call.seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "ONLY_SELLER_OR_TOKEN_OWNER");

        emit CallCanceled(_tokenContract, _tokenId, call);

        // Remove the option from storage
        delete callForNFT[_tokenContract][_tokenId];
    }

    ///                                                          ///
    ///                         BUY CALL                         ///
    ///                                                          ///

    /// @notice Emitted when a covered call option is purchased
    /// @param tokenContract The ERC-721 token address of the purchased call option
    /// @param tokenId The ERC-721 token id of the purchased call option
    /// @param call The metadata of the purchased call option
    event CallPurchased(address tokenContract, uint256 tokenId, Call call);

    /// @notice Purchases a call option for an NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ERC-721 token id
    /// @param _strike The strike price of the option
    function buyCall(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _strike
    ) external payable nonReentrant {
        // Get the option for the specified token
        Call storage call = callForNFT[_tokenContract][_tokenId];

        // Ensure the option has not been purchased
        require(call.buyer == address(0), "INVALID_PURCHASE");

        // Ensure the option has not expired
        require(call.expiry > block.timestamp, "INVALID_CALL");

        // Ensure the specified strike matches the call strike
        require(call.strike == _strike, "MUST_MATCH_STRIKE");

        // Cache the premium price
        uint256 premium = call.premium;

        // Ensure the attached ETH matches the premium
        require(msg.value == premium, "MUST_MATCH_PREMIUM");

        // Mark the option as purchased
        call.buyer = msg.sender;

        // Cache the seller address
        address seller = call.seller;

        // Transfer the NFT from the seller into escrow for the duration of the option
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, seller, address(this), _tokenId);

        // Transfer the premium to the seller
        _handleOutgoingTransfer(seller, premium, address(0), 50000);

        emit CallPurchased(_tokenContract, _tokenId, call);
    }

    ///                                                          ///
    ///                       EXERCISE CALL                      ///
    ///                                                          ///

    /// @notice Emitted when a covered call option is exercised
    /// @param tokenContract The ERC-721 token address of the exercised call option
    /// @param tokenId The ERC-721 token id of the exercised call option
    /// @param call The metadata of the exercised call option
    event CallExercised(address tokenContract, uint256 tokenId, Call call);

    /// @notice Exercises a purchased call option for an NFT
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    function exerciseCall(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        // Get the option for the specified token
        Call memory call = callForNFT[_tokenContract][_tokenId];

        // Ensure the caller is the buyer
        require(call.buyer == msg.sender, "ONLY_BUYER");

        // Ensure the option has not expired
        require(call.expiry > block.timestamp, "INVALID_EXERCISE");

        // Cache the strike price
        uint256 strike = call.strike;

        // Ensure the attached ETH matches the strike
        require(msg.value == strike, "MUST_MATCH_STRIKE");

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, strike, address(0), 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(call.seller, remainingProfit, address(0), 50000);

        // Transfer the NFT to the buyer
        IERC721(_tokenContract).transferFrom(address(this), msg.sender, _tokenId);

        emit CallExercised(_tokenContract, _tokenId, call);

        // Remove the option from storage
        delete callForNFT[_tokenContract][_tokenId];
    }

    ///                                                          ///
    ///                        RECLAIM CALL                      ///
    ///                                                          ///

    /// @notice Emitted when the NFT from an expired call option is reclaimed
    /// @param tokenContract The ERC-721 token address of the expired call option
    /// @param tokenId The ERC-721 token id of the expired call option
    /// @param call The metadata of the expired call option
    event CallReclaimed(address tokenContract, uint256 tokenId, Call call);

    /// @notice Reclaims the NFT from an expired call option
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    function reclaimCall(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the option for the specified token
        Call memory call = callForNFT[_tokenContract][_tokenId];

        // Cache the seller address
        address seller = call.seller;

        // Ensure the caller is the seller
        require(msg.sender == seller, "ONLY_SELLER");

        // Ensure the option has been purchased
        require(call.buyer != address(0), "INVALID_RECLAIM");

        // Ensure the option has expired
        require(block.timestamp >= call.expiry, "ACTIVE_OPTION");

        // Transfer the NFT back to seller
        IERC721(_tokenContract).transferFrom(address(this), seller, _tokenId);

        emit CallReclaimed(_tokenContract, _tokenId, call);

        // Remove the option from storage
        delete callForNFT[_tokenContract][_tokenId];
    }
}
