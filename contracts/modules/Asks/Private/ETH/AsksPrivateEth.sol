// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {IAsksPrivateEth} from "./IAsksPrivateEth.sol";

/// @title Asks Private ETH
/// @author kulkarohan
/// @notice Module enabling ETH asks for ERC-721 tokens with specified buyers
contract AsksPrivateEth is IAsksPrivateEth, ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                          IMMUTABLES                      ///
    ///                                                          ///

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    ///                                                          ///
    ///                          CONSTRUCTOR                     ///
    ///                                                          ///

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
        ModuleNamingSupportV1("Asks Private ETH")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    ///                                                          ///
    ///                            EIP-165                       ///
    ///                                                          ///

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IAsksPrivateEth).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    ///                                                          ///
    ///                          ASK STORAGE                     ///
    ///                                                          ///

    /// @notice The metadata for a given ask
    /// @param seller The address of the seller
    /// @param price The price to fill the ask
    /// @param buyer The address of the buyer
    struct Ask {
        address seller;
        uint96 price;
        address buyer;
    }

    /// @notice The ask for a given NFT
    /// @dev ERC-721 token contract => ERC-721 token id => Ask
    mapping(address => mapping(uint256 => Ask)) public askForNFT;

    ///                                                          ///
    ///                          CREATE ASK                      ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------------.
    //     / \            |AsksPrivateEth|
    //   Caller           `------+-------'
    //     |     createAsk()     |
    //     | -------------------->
    //     |                     |
    //     |                     |----.
    //     |                     |    | store ask metadata
    //     |                     |<---'
    //     |                     |
    //     |                     |----.
    //     |                     |    | emit AskCreated()
    //     |                     |<---'
    //   Caller           ,------+-------.
    //     ,-.            |AsksPrivateEth|
    //     `-'            `--------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is created
    /// @param tokenContract The ERC-721 token address of the created ask
    /// @param tokenId The ERC-721 token id of the created ask
    /// @param ask The metadata of the created ask
    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _price The price to fill the ask
    /// @param _buyer The address to fill the ask
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _buyer
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        // Get the storage pointer to the token
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        // Store the associated metadata
        ask.seller = tokenOwner;
        ask.price = uint96(_price);
        ask.buyer = _buyer;

        emit AskCreated(_tokenContract, _tokenId, ask);
    }

    ///                                                          ///
    ///                          UPDATE ASK                      ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------------.
    //     / \            |AsksPrivateEth|
    //   Caller           `------+-------'
    //     |    setAskPrice()    |
    //     | -------------------->
    //     |                     |
    //     |                     |----.
    //     |                     |    | update ask price
    //     |                     |<---'
    //     |                     |
    //     |                     |----.
    //     |                     |    | emit AskPriceUpdated()
    //     |                     |<---'
    //   Caller           ,------+-------.
    //     ,-.            |AsksPrivateEth|
    //     `-'            `--------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is updated
    /// @param tokenContract The ERC-721 token address of the updated ask
    /// @param tokenId The ERC-721 token id of the updated ask
    /// @param ask The metadata of the updated ask
    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

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
        ask.price = uint96(_price);

        emit AskPriceUpdated(_tokenContract, _tokenId, ask);
    }

    ///                                                          ///
    ///                          CANCEL ASK                      ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------------.
    //     / \            |AsksPrivateEth|
    //   Caller           `------+-------'
    //     |     cancelAsk()     |
    //     | -------------------->
    //     |                     |
    //     |                     |----.
    //     |                     |    | emit AskCanceled()
    //     |                     |<---'
    //     |                     |
    //     |                     |----.
    //     |                     |    | delete ask
    //     |                     |<---'
    //   Caller           ,------+-------.
    //     ,-.            |AsksPrivateEth|
    //     `-'            `--------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is canceled
    /// @param tokenContract The ERC-721 token address of the canceled ask
    /// @param tokenId The ERC-721 token id of the canceled ask
    /// @param ask The metadata of the canceled ask
    event AskCanceled(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Cancels the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the ask for the specified token
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        // Ensure the caller is the seller or a new token owner
        require(msg.sender == ask.seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "ONLY_SELLER_OR_TOKEN_OWNER");

        emit AskCanceled(_tokenContract, _tokenId, ask);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }

    ///                                                          ///
    ///                           FILL ASK                       ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------------.           ,--------------------.
    //     / \            |AsksPrivateEth|           |ERC721TransferHelper|
    //   Caller           `------+-------'           `---------+----------'
    //     |      fillAsk()      |                             |
    //     | -------------------->                             |
    //     |                     |                             |
    //     |                     |----.                        |
    //     |                     |    | validate caller        |
    //     |                     |<---'                        |
    //     |                     |                             |
    //     |                     |----.                        |
    //     |                     |    | validate received ETH  |
    //     |                     |<---'                        |
    //     |                     |                             |
    //     |                     |----.                        |
    //     |                     |    | handle royalty payouts |
    //     |                     |<---'                        |
    //     |                     |                             |
    //     |                     |----.                        |
    //     |                     |    | handle seller payout   |
    //     |                     |<---'                        |
    //     |                     |                             |
    //     |                     |        transferFrom()       |
    //     |                     | ---------------------------->
    //     |                     |                             |
    //     |                     |                             |----.
    //     |                     |                             |    | transfer NFT from seller to buyer
    //     |                     |                             |<---'
    //     |                     |                             |
    //     |                     |----.                        |
    //     |                     |    | emit AskFilled()       |
    //     |                     |<---'                        |
    //     |                     |                             |
    //     |                     |----.
    //     |                     |    | delete ask from contract
    //     |                     |<---'
    //   Caller           ,------+-------.           ,---------+----------.
    //     ,-.            |AsksPrivateEth|           |ERC721TransferHelper|
    //     `-'            `--------------'           `--------------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is filled
    /// @param tokenContract The ERC-721 token address of the filled ask
    /// @param tokenId The ERC-721 token id of the filled ask
    /// @param ask The metadata of the filled ask
    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

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

        // Ensure the caller is the specified buyer
        require(msg.sender == ask.buyer, "ONLY_BUYER");

        // Cache the price
        uint256 price = ask.price;

        // Ensure the attached ETH matches the price
        require(msg.value == price, "PRICE_MISMATCH");

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, price, address(0), 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(seller, remainingProfit, address(0), 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper
        erc721TransferHelper.transferFrom(_tokenContract, seller, msg.sender, _tokenId);

        emit AskFilled(_tokenContract, _tokenId, ask);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }
}
