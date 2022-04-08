// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {IncomingTransferSupportV1} from "../../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {IAsksCoreErc20} from "./IAsksCoreErc20.sol";

/// @title Asks Core ERC-20
/// @author kulkarohan
/// @notice Module for minimal ERC-20 asks for ERC-721 tokens
contract AsksCoreErc20 is ReentrancyGuard, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                        IMMUTABLES                        ///
    ///                                                          ///

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

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
        ModuleNamingSupportV1("Asks Core ERC-20")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IAsksCoreErc20).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    ///                                                          ///
    ///                        ASK STORAGE                       ///
    ///                                                          ///

    /// @notice The metadata for a given ask
    /// @param seller The address of the seller
    /// @param price The price to fill the ask
    /// @param currency The address of the ERC-20 currency, or address(0) for ETH
    struct Ask {
        address seller;
        uint96 price;
        address currency;
    }

    /// @notice The ask for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token id => Ask
    mapping(address => mapping(uint256 => Ask)) public askForNFT;

    ///                                                          ///
    ///                        CREATE ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-------------.
    //     / \            |AsksCoreErc20|
    //   Caller           `------+------'
    //     |     createAsk()     |
    //     | ------------------->|
    //     |                     |
    //     |                     ----.
    //     |                         | store ask metadata
    //     |                     <---'
    //     |                     |
    //     |                     ----.
    //     |                         | emit AskCreated()
    //     |                     <---'
    //   Caller           ,------+------.
    //     ,-.            |AsksCoreErc20|
    //     `-'            `-------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is created
    /// @param tokenContract The ERC-721 token address of the created ask
    /// @param tokenId The ERC-721 token id of the created ask
    /// @param ask The metadata of the created ask
    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency of the ask price
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender), "ONLY_TOKEN_OWNER_OR_OPERATOR");

        // Ensure the price can be downcasted to 96 bits for this module
        // For a higher ask price, use the supporting module
        require(_price <= type(uint96).max, "INVALID_ASK_PRICE");

        // Store the ask metadata
        askForNFT[_tokenContract][_tokenId].seller = tokenOwner;
        askForNFT[_tokenContract][_tokenId].price = uint96(_price);
        askForNFT[_tokenContract][_tokenId].currency = _currency;

        emit AskCreated(_tokenContract, _tokenId, askForNFT[_tokenContract][_tokenId]);
    }

    ///                                                          ///
    ///                        UPDATE ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-------------.
    //     / \            |AsksCoreErc20|
    //   Caller           `------+------'
    //     |    setAskPrice()    |
    //     | ------------------->|
    //     |                     |
    //     |                     |
    //     |    _______________________________________
    //     |    ! ALT  /  price change?                !
    //     |    !_____/          |                     !
    //     |    !                ----.                 !
    //     |    !                    | update price    !
    //     |    !                <---'                 !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                     |
    //     |                     |
    //     |    __________________________________________
    //     |    ! ALT  /  currency change?                !
    //     |    !_____/          |                        !
    //     |    !                ----.                    !
    //     |    !                    | update currency    !
    //     |    !                <---'                    !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                     |
    //     |                     ----.
    //     |                         | emit AskPriceUpdated()
    //     |                     <---'
    //   Caller           ,------+------.
    //     ,-.            |AsksCoreErc20|
    //     `-'            `-------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask price is updated
    /// @param tokenContract The ERC-721 token address of the updated ask
    /// @param tokenId The ERC-721 token id of the updated ask
    /// @param ask The metadata of the updated the ask
    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Updates the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency of the ask price
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external nonReentrant {
        // Get the ask for the specified token
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        // Ensure the caller is seller
        require(msg.sender == ask.seller, "ONLY_SELLER");

        // If updating the price,
        if (_price != ask.price) {
            // Ensure the price to set can be downcasted
            require(_price <= type(uint96).max, "INVALID_ASK_PRICE");

            // Store the new price
            ask.price = uint96(_price);
        }

        // If updating the currency,
        if (_currency != ask.currency) {
            // Store the new currency
            ask.currency = _currency;
        }

        emit AskPriceUpdated(_tokenContract, _tokenId, ask);
    }

    ///                                                          ///
    ///                        CANCEL ASK                        ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-------------.
    //     / \            |AsksCoreErc20|
    //   Caller           `------+------'
    //     |     cancelAsk()     |
    //     | ------------------->|
    //     |                     |
    //     |                     ----.
    //     |                         | emit AskCanceled()
    //     |                     <---'
    //     |                     |
    //     |                     ----.
    //     |                         | delete ask
    //     |                     <---'
    //   Caller           ,------+------.
    //     ,-.            |AsksCoreErc20|
    //     `-'            `-------------'
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
        Ask memory ask = askForNFT[_tokenContract][_tokenId];

        // Ensure the caller is the seller or a new owner of the token
        require(msg.sender == ask.seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "ONLY_SELLER_OR_TOKEN_OWNER");

        emit AskCanceled(_tokenContract, _tokenId, ask);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }

    ///                                                          ///
    ///                         FILL ASK                         ///
    ///                                                          ///

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,-------------.            ,--------------------.
    //     / \            |AsksCoreErc20|            |ERC721TransferHelper|
    //   Caller           `------+------'            `---------+----------'
    //     |      fillAsk()      |                             |
    //     | ------------------->|                             |
    //     |                     |                             |
    //     |                     ----.
    //     |                         | validate received payment
    //     |                     <---'
    //     |                     |                             |
    //     |                     ----.                         |
    //     |                         | handle royalty payouts  |
    //     |                     <---'                         |
    //     |                     |                             |
    //     |                     ----.                         |
    //     |                         | handle seller payout    |
    //     |                     <---'                         |
    //     |                     |                             |
    //     |                     |       transferFrom()        |
    //     |                     |----------------------------->
    //     |                     |                             |
    //     |                     |                             |----.
    //     |                     |                             |    | transfer NFT from seller to buyer
    //     |                     |                             |<---'
    //     |                     |                             |
    //     |                     ----.                         |
    //     |                         | emit AskFilled()        |
    //     |                     <---'                         |
    //     |                     |                             |
    //     |                     ----.                         |
    //     |                         | delete ask from contract|
    //     |                     <---'                         |
    //   Caller           ,------+------.            ,---------+----------.
    //     ,-.            |AsksCoreErc20|            |ERC721TransferHelper|
    //     `-'            `-------------'            `--------------------'
    //     /|\
    //      |
    //     / \

    /// @notice Emitted when an ask is filled
    /// @param tokenContract The ERC-721 token address of the filled ask
    /// @param tokenId The ERC-721 token id of the filled ask
    /// @param buyer The buyer address of the filled ask
    /// @param ask The metadata of the filled ask
    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, address buyer, Ask ask);

    /// @notice Fills the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency to fill the ask
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external payable nonReentrant {
        // Get the ask for the specified token
        Ask memory ask = askForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = ask.seller;

        // Ensure the ask is active
        require(seller != address(0), "INACTIVE_ASK");

        // Cache the price
        uint256 price = ask.price;

        // Ensure the specified price matches the ask price
        require(_price == price, "MUST_MATCH_PRICE");

        // Cache the currency
        address currency = ask.currency;

        // Ensure the specified currency matches the ask currency
        require(_currency == currency, "MUST_MATCH_CURRENCY");

        // Transfer the ask price from the buyer
        // If ETH, this reverts if the buyer did not attach enough
        // If ERC-20, this reverts if the buyer did not approve the ERC20TransferHelper or does not own the specified tokens
        _handleIncomingTransfer(price, currency);

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, price, currency, 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, currency);

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(seller, remainingProfit, currency, 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(_tokenContract, seller, msg.sender, _tokenId);

        emit AskFilled(_tokenContract, _tokenId, msg.sender, ask);

        // Remove the ask from storage
        delete askForNFT[_tokenContract][_tokenId];
    }
}
