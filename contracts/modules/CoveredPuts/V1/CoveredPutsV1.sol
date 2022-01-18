// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Covered Puts V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to place covered put options on NFTs
contract CoveredPutsV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The number of covered put options placed
    uint256 public putCount;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata of a covered put option
    /// @param buyer The address of the NFT buyer placing the put option
    /// @param seller The address of the NFT seller, or address(0) if not purchased
    /// @param currency The address of the ERC-20, or address(0) for ETH, denominating the option
    /// @param premium The premium price to purchase the put option
    /// @param strike The strike price for an exercised put option
    /// @param expiration The expiration time of the put option
    struct Put {
        address buyer;
        address seller;
        address currency;
        uint256 premium;
        uint256 strike;
        uint256 expiration;
    }

    /// ------------ STORAGE ------------

    /// @notice The metadata for a covered put option
    /// @dev ERC-721 token address => ERC-721 token ID => Put ID => Put
    mapping(address => mapping(uint256 => mapping(uint256 => Put))) public puts;

    /// @notice The covered put options placed on a given NFT
    /// @dev ERC-721 token address => ERC-721 token ID => put IDs
    mapping(address => mapping(uint256 => uint256[])) public putsForNFT;

    /// ------------ EVENTS ------------

    /// @notice Emitted when a covered put option is created
    /// @param tokenContract The ERC-721 token address of the created put option
    /// @param tokenId The ERC-721 token ID of the created put option
    /// @param put The metadata of the created caputll option
    event PutCreated(address indexed tokenContract, uint256 indexed tokenId, Put put);

    /// @notice Emitted when a covered put option is canceled
    /// @param tokenContract The ERC-721 token address of the canceled put option
    /// @param tokenId The ERC-721 token ID of the canceled put option
    /// @param put The metadata of the canceled put option
    event PutCanceled(address indexed tokenContract, uint256 indexed tokenId, Put put);

    /// @notice Emitted when the ETH/ERC-20 from an expired put option is reclaimed
    /// @param tokenContract The ERC-721 token address of the reclaimed put option
    /// @param tokenId The ERC-721 token ID of the reclaimed put option
    /// @param put The metadata of the reclaimed put option
    event PutReclaimed(address indexed tokenContract, uint256 indexed tokenId, address buyer, Put put);

    /// @notice Emitted when a covered put option is purchased
    /// @param tokenContract The ERC-721 token address of the purchased put option
    /// @param tokenId The ERC-721 token ID of the purchased put option
    /// @param seller The NFT seller address who purchased the put option
    /// @param put The metadata of the purchased put option
    event PutPurchased(address indexed tokenContract, uint256 indexed tokenId, address seller, Put put);

    /// @notice Emitted when a covered put option is exercised
    /// @param tokenContract The ERC-721 token address of the exercised put option
    /// @param tokenId The ERC-721 token ID of the exercised put option
    /// @param seller The NFT seller address who exercised the put option
    /// @param put The metadata of the exercised put option
    event PutExercised(address indexed tokenContract, uint256 indexed tokenId, address seller, Put put);

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
        ModuleNamingSupportV1("Covered Puts: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ NFT BUYER FUNCTIONS ------------

    /// @notice Places a covered put option on an NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _premiumPrice The amount to purchase the put option
    /// @param _strikePrice The amount of ETH/ERC-20 for an exercised put option
    /// @param _expiration The expiration time of the put option
    /// @param _currency The address of the ERC-20, or address(0) for ETH, to denominate the put option
    function createPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _premiumPrice,
        uint256 _strikePrice,
        uint256 _expiration,
        address _currency
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createPut cannot create put on owned NFT");
        require(_expiration > block.timestamp, "createCall _expiration must be future time");

        // Hold strike amount in escrow
        _handleIncomingTransfer(_strikePrice, _currency);

        putCount++;

        puts[_tokenContract][_tokenId][putCount] = Put({
            buyer: msg.sender,
            seller: payable(address(0)),
            currency: _currency,
            premium: _premiumPrice,
            strike: _strikePrice,
            expiration: _expiration
        });

        putsForNFT[_tokenContract][_tokenId].push(putCount);

        emit PutCreated(_tokenContract, _tokenId, puts[_tokenContract][_tokenId][putCount]);

        return putCount;
    }

    /// @notice Cancels a covered put option and refunds the strike amount, if not purchased
    /// @param _putId The ID of the covered put option
    function cancelPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        Put storage put = puts[_tokenContract][_tokenId][_putId];

        require(put.buyer == msg.sender, "cancelPut must be buyer");
        require(put.seller == address(0), "cancelPut put has been purchased");

        _handleOutgoingTransfer(msg.sender, put.strike, put.currency, USE_ALL_GAS_FLAG);

        emit PutCanceled(_tokenContract, _tokenId, put);

        delete puts[_tokenContract][_tokenId][_putId];
    }

    /// @notice Refunds the ETH/ERC-20 strike from a purchased, but non-exercised put option
    /// @param _putId The ID of the covered put option
    function reclaimPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        Put storage put = puts[_tokenContract][_tokenId][_putId];

        require(put.buyer == msg.sender, "reclaimPut must be buyer");
        require(put.seller != address(0), "reclaimPut put not purchased");
        require(block.timestamp >= put.expiration, "reclaimPut put is active");

        _handleOutgoingTransfer(put.buyer, put.strike, put.currency, USE_ALL_GAS_FLAG);

        emit PutReclaimed(_tokenContract, _tokenId, msg.sender, put);

        delete puts[_tokenContract][_tokenId][_putId];
    }

    /// ------------ NFT SELLER FUNCTIONS ------------

    /// @notice Purchases a put option, transferring the premium to the buyer
    /// @notice The ID of the covered put option
    function buyPut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external payable nonReentrant {
        Put storage put = puts[_tokenContract][_tokenId][_putId];

        require(put.buyer != address(0), "buyPut put does not exist");
        require(put.seller == address(0), "buyPut put already purchased");
        require(put.expiration > block.timestamp, "buyPut put expired");

        // Take premium from NFT holder (for option to sell)
        _handleIncomingTransfer(put.premium, put.currency);
        // Send premium to buyer
        _handleOutgoingTransfer(put.buyer, put.premium, put.currency, USE_ALL_GAS_FLAG);

        put.seller = msg.sender;

        emit PutPurchased(_tokenContract, _tokenId, msg.sender, put);
    }

    /// @notice Exercises a put option, transferring the NFT to the buyer and strike amount to the seller
    /// @notice The ID of the covered put option
    function exercisePut(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _putId
    ) external nonReentrant {
        Put storage put = puts[_tokenContract][_tokenId][_putId];

        require(put.seller == msg.sender, "exercisePut must be seller");
        require(msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "exercisePut must own token");
        require(put.expiration > block.timestamp, "exercisePut put expired");

        // Payout respective parties, ensuring NFT royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, put.strike, put.currency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, put.currency);

        // Transfer remaining strike to NFT seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, put.currency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, put.buyer, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: put.currency, tokenId: 0, amount: put.strike});

        emit ExchangeExecuted(put.seller, put.buyer, userAExchangeDetails, userBExchangeDetails);
        emit PutExercised(_tokenContract, _tokenId, msg.sender, put);

        delete puts[_tokenContract][_tokenId][_putId];
    }
}
