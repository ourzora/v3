// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Covered Puts ETH
/// @author kulkarohan
/// @notice Module for minimal ETH covered put options for ERC-721 tokens
contract CoveredPutsEth is ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
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
        ModuleNamingSupportV1("Covered Puts ETH")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    ///                                                          ///
    ///                         PUT STORAGE                      ///
    ///                                                          ///

    /// @notice The metadata for a covered put option
    /// @param seller The address of the seller
    /// @param premium The price to purchase the option
    /// @param buyer The address of the buyer, or address(0) if not yet purchased
    /// @param strike The price to exercise the option
    /// @param expiry The expiration time of the option
    struct Put {
        address seller;
        uint96 premium;
        address buyer;
        uint96 strike;
        uint256 expiry;
    }

    /// @notice The number of covered put options placed
    uint256 public putCount;

    /// @notice The covered put option for a given NFT
    /// @dev ERC-721 token address => ERC-721 token id => Put id
    mapping(address => mapping(uint256 => mapping(uint256 => Put))) public puts;

    ///                                                          ///
    ///                         CREATE PUT                       ///
    ///                                                          ///

    /// @notice Emitted when a covered put option is created
    /// @param tokenContract The ERC-721 token address of the created put option
    /// @param tokenId The ERC-721 token id of the created put option
    /// @param putId The id of the created put option
    /// @param put The metadata of the created put option
    event PutCreated(address tokenContract, uint256 tokenId, uint256 putId, Put put);

    /// @notice Creates a covered put option for an NFT
    /// @dev The amount of ETH attached is held in escrow as the strike
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _premium The purchase price
    /// @param _expiry The expiration time
    /// @return The created put option id
    function createPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _premium,
        uint256 _expiry
    ) external payable nonReentrant returns (uint256) {
        // Used to store the option id
        uint256 putId;

        // Get the next available option id
        // The increment cannot realistically overflow
        unchecked {
            putId = ++putCount;
        }

        // Used to store the option metadata
        Put storage put = puts[_tokenContract][_tokenId][putId];

        // Store the caller as the seller
        put.seller = msg.sender;

        // Store the specified premium
        // The maximum value this holds is greater than the total supply of ETH
        put.premium = uint96(_premium);

        // Store the amount of ETH attached as the strike
        // Peep 4 lines above
        put.strike = uint96(msg.value);

        // Store the specified expiration time
        put.expiry = _expiry;

        emit PutCreated(_tokenContract, _tokenId, putId, put);

        // Return the option id
        return putId;
    }

    ///                                                          ///
    ///                         CANCEL PUT                       ///
    ///                                                          ///

    /// @notice Emitted when a covered put option is canceled
    /// @param tokenContract The ERC-721 token address of the canceled put option
    /// @param tokenId The ERC-721 token id of the canceled put option
    /// @param putId The id of the canceled put option
    /// @param put The metadata of the canceled put option
    event PutCanceled(address tokenContract, uint256 tokenId, uint256 putId, Put put);

    /// @notice Cancels a put option that has not yet been purchased
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _putId The put option id
    function cancelPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        // Get the specified option
        Put memory put = puts[_tokenContract][_tokenId][_putId];

        // Ensure the caller is the seller
        require(put.seller == msg.sender, "ONLY_SELLER");

        // Ensure the option has not been purchased
        require(put.buyer == address(0), "PURCHASED");

        // Refund the strike to the seller
        _handleOutgoingTransfer(msg.sender, put.strike, address(0), 50000);

        emit PutCanceled(_tokenContract, _tokenId, _putId, put);

        // Remove the option from storage
        delete puts[_tokenContract][_tokenId][_putId];
    }

    ///                                                          ///
    ///                          BUY PUT                         ///
    ///                                                          ///

    /// @notice Emitted when a covered put option is purchased
    /// @param tokenContract The ERC-721 token address of the purchased put option
    /// @param tokenId The ERC-721 token id of the purchased put option
    /// @param putId The id of the purchased put option
    /// @param put The metadata of the purchased put option
    event PutPurchased(address tokenContract, uint256 tokenId, uint256 putId, Put put);

    /// @notice Purchases a put option for an NFT
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _putId The put option id
    /// @param _strike The strike price held in escrow
    function buyPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId,
        uint256 _strike
    ) external payable nonReentrant {
        // Get the specified option
        Put storage put = puts[_tokenContract][_tokenId][_putId];

        // Ensure the option has not been purchased
        require(put.buyer == address(0), "PURCHASED");

        // Ensure the option has not expired
        require(put.expiry > block.timestamp, "EXPIRED");

        // Ensure the specified strike matches the option strike
        require(put.strike == _strike, "INVALID_STRIKE");

        // Cache the premium price
        uint256 premium = put.premium;

        // Ensure the attached ETH matches the premium
        require(msg.value == premium, "INVALID_PREMIUM");

        // Mark the option as purchased
        put.buyer = msg.sender;

        // Transfer the premium to seller
        _handleOutgoingTransfer(put.seller, premium, address(0), 50000);

        emit PutPurchased(_tokenContract, _tokenId, _putId, put);
    }

    ///                                                          ///
    ///                        EXERCISE PUT                      ///
    ///                                                          ///

    /// @notice Emitted when a covered put option is exercised
    /// @param tokenContract The ERC-721 token address of the exercised put option
    /// @param tokenId The ERC-721 token id of the exercised put option
    /// @param putId The id of the exercised put option
    /// @param put The metadata of the exercised put option
    event PutExercised(address tokenContract, uint256 tokenId, uint256 putId, Put put);

    /// @notice Exercises a purchased put option
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _putId The put option id
    function exercisePut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        // Get the specified option
        Put memory put = puts[_tokenContract][_tokenId][_putId];

        // Ensure the caller is the buyer
        require(put.buyer == msg.sender, "ONLY_BUYER");

        // Ensure the option has not expired
        require(put.expiry > block.timestamp, "EXPIRED");

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, put.strike, address(0), 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the option buyer
        _handleOutgoingTransfer(msg.sender, remainingProfit, address(0), 50000);

        // Transfer the NFT to the seller
        // Reverts if the buyer did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, put.seller, _tokenId);

        emit PutExercised(_tokenContract, _tokenId, _putId, put);

        // Remove the option from storage
        delete puts[_tokenContract][_tokenId][_putId];
    }

    ///                                                          ///
    ///                        RECLAIM PUT                       ///
    ///                                                          ///

    /// @notice Emitted when the strike from an expired put option is reclaimed
    /// @param tokenContract The ERC-721 token address of the reclaimed put option
    /// @param tokenId The ERC-721 token id of the reclaimed put option
    /// @param putId The id of the reclaimed put option
    /// @param put The metadata of the reclaimed put option
    event PutReclaimed(address tokenContract, uint256 tokenId, uint256 putId, Put put);

    /// @notice Reclaims the ETH from an expired put option
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _putId The put option id
    function reclaimPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        // Get the specified option
        Put memory put = puts[_tokenContract][_tokenId][_putId];

        // Ensure the caller is the seller
        require(put.seller == msg.sender, "ONLY_SELLER");

        // Ensure the option has been purchased
        require(put.buyer != address(0), "NOT_PURCHASED");

        // Ensure the option has expired
        require(block.timestamp >= put.expiry, "NOT_EXPIRED");

        // Transfer the strike back to the seller
        _handleOutgoingTransfer(msg.sender, put.strike, address(0), 50000);

        emit PutReclaimed(_tokenContract, _tokenId, _putId, put);

        // Remove the option from storage
        delete puts[_tokenContract][_tokenId][_putId];
    }
}
