// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {IAsksCoreEth} from "./IAsksCoreEth.sol";

/// @title Asks Core ETH
/// @author kulkarohan
/// @notice Module for minimal ETH asks for ERC-721 tokens
contract AsksCoreEth is ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                        IMMUTABLES                        ///
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
        ModuleNamingSupportV1("Asks Core ETH")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IAsksCoreEth).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    ///                                                          ///
    ///                        ASK STORAGE                       ///
    ///                                                          ///

    /// @notice The metadata for a given ask
    /// @param seller The address of the seller
    /// @param price The price to fill the ask
    struct Ask {
        address seller;
        uint96 price;
    }

    /// @notice The ask for a given NFT
    /// @dev ERC-721 token contract => ERC-721 token id => Ask
    mapping(address => mapping(uint256 => Ask)) public askForNFT;

    ///                                                          ///
    ///                        CREATE ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-----------.
    //     / \            |AsksCoreEth|
    //   Caller           `-----+-----'
    //     |    createAsk()     |
    //     | ------------------>|
    //     |                    |
    //     |                    ----.
    //     |                        | store ask metadata
    //     |                    <---'
    //     |                    |
    //     |                    ----.
    //     |                        | emit AskCreated()
    //     |                    <---'
    //   Caller           ,-----+-----.
    //     ,-.            |AsksCoreEth|
    //     `-'            `-----------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is created
    /// @param tokenContract The ERC-721 token address of the created ask
    /// @param tokenId The ERC-721 token id of the created ask
    /// @param seller The seller address of the created ask
    /// @param price The price of the created ask
    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, address seller, uint256 price);

    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        // Store the owner as the seller
        askForNFT[_tokenContract][_tokenId].seller = tokenOwner;

        // Store the ask price
        // The max value for this module is 2^96 - 1, which is magnitudes higher than the total supply of ETH
        askForNFT[_tokenContract][_tokenId].price = uint96(_price);

        emit AskCreated(_tokenContract, _tokenId, tokenOwner, _price);
    }

    ///                                                          ///
    ///                        UPDATE ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-----------.
    //     / \            |AsksCoreEth|
    //   Caller           `-----+-----'
    //     |   setAskPrice()    |
    //     | ------------------>|
    //     |                    |
    //     |                    ----.
    //     |                        | update ask price
    //     |                    <---'
    //     |                    |
    //     |                    ----.
    //     |                        | emit AskPriceUpdated()
    //     |                    <---'
    //   Caller           ,-----+-----.
    //     ,-.            |AsksCoreEth|
    //     `-'            `-----------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is updated
    /// @param tokenContract The ERC-721 token address of the updated ask
    /// @param tokenId The ERC-721 token id of the updated ask
    /// @param seller The user that updated the ask
    /// @param price The updated price of the ask
    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, address seller, uint256 price);

    /// @notice Updates the ask price for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The ask price to set
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        // Get the ask for the specified token
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        // Ensure the caller is seller
        require(msg.sender == ask.seller, "ONLY_SELLER");

        // Update the ask price
        // The max value for this module is 2^96 - 1, which is magnitudes higher than the total supply of ETH
        ask.price = uint96(_price);

        emit AskPriceUpdated(_tokenContract, _tokenId, msg.sender, _price);
    }

    ///                                                          ///
    ///                        CANCEL ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-----------.
    //     / \            |AsksCoreEth|
    //   Caller           `-----+-----'
    //     |    cancelAsk()     |
    //     | ------------------>|
    //     |                    |
    //     |                    ----.
    //     |                        | emit AskCanceled()
    //     |                    <---'
    //     |                    |
    //     |                    ----.
    //     |                        | delete ask
    //     |                    <---'
    //   Caller           ,-----+-----.
    //     ,-.            |AsksCoreEth|
    //     `-'            `-----------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is canceled
    /// @param tokenContract The ERC-721 token address of the canceled ask
    /// @param tokenId The ERC-721 token id of the canceled ask
    /// @param seller The user that canceled the ask
    /// @param price The price of the canceled ask
    event AskCanceled(address indexed tokenContract, uint256 indexed tokenId, address seller, uint256 price);

    /// @notice Cancels the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the ask for the specified token
        Ask memory ask = askForNFT[_tokenContract][_tokenId];

        // Cache the seller address
        address seller = ask.seller;

        // Ensure the caller is the seller or a new token owner
        require(msg.sender == seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "ONLY_SELLER_OR_TOKEN_OWNER");

        emit AskCanceled(_tokenContract, _tokenId, seller, ask.price);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }

    ///                                                          ///
    ///                         FILL ASK                         ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-----------.            ,--------------------.
    //     / \            |AsksCoreEth|            |ERC721TransferHelper|
    //   Caller           `-----+-----'            `---------+----------'
    //     |     fillAsk()      |                            |
    //     | ------------------>|                            |
    //     |                    |                            |
    //     |                    ----.                        |
    //     |                        | validate received ETH  |
    //     |                    <---'                        |
    //     |                    |                            |
    //     |                    ----.                        |
    //     |                        | handle royalty payouts |
    //     |                    <---'                        |
    //     |                    |                            |
    //     |                    ----.                        |
    //     |                        | handle seller payout   |
    //     |                    <---'                        |
    //     |                    |                            |
    //     |                    |       transferFrom()       |
    //     |                    |---------------------------->
    //     |                    |                            |
    //     |                    |                            |----.
    //     |                    |                            |    | transfer NFT from seller to buyer
    //     |                    |                            |<---'
    //     |                    |                            |
    //     |                    ----.                        |
    //     |                        | emit AskFilled()       |
    //     |                    <---'                        |
    //     |                    |                            |
    //     |                    ----.
    //     |                        | delete ask from contract
    //     |                    <---'
    //   Caller           ,-----+-----.            ,---------+----------.
    //     ,-.            |AsksCoreEth|            |ERC721TransferHelper|
    //     `-'            `-----------'            `--------------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is filled
    /// @param tokenContract The ERC-721 token address of the filled ask
    /// @param tokenId The ERC-721 token id of the filled ask
    /// @param buyer The buyer address of the filled ask
    /// @param seller The seller address of the filled ask
    /// @param price The price of the filled ask
    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, address buyer, address seller, uint256 price);

    /// @notice Fills the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function fillAsk(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        // Get the ask for the specified token
        Ask memory ask = askForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = ask.seller;

        // Ensure the ask is active
        require(seller != address(0), "INACTIVE_ASK");

        // Cache the price
        uint256 price = ask.price;

        // Ensure the attached ETH matches the price
        require(msg.value == price, "MUST_MATCH_PRICE");

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, price, address(0), 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(seller, remainingProfit, address(0), 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, seller, msg.sender, _tokenId);

        emit AskFilled(_tokenContract, _tokenId, msg.sender, seller, price);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }
}
