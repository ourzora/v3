// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Asks V1.1
/// @author tbtstl <t@zora.co>
/// @notice This module allows sellers to list an owned ERC-721 token for sale for a given price in a given currency, and allows buyers to purchase from those asks
contract AsksV1_1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The ask for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token ID => Ask
    mapping(address => mapping(uint256 => Ask)) public askForNFT;

    /// @notice The metadata for an ask
    /// @param seller The address of the seller placing the ask
    /// @param sellerFundsRecipient The address to send funds after the ask is filled
    /// @param askCurrency The address of the ERC-20, or address(0) for ETH, required to fill the ask
    /// @param findersFeeBps The fee to the referrer of the ask
    /// @param askPrice The price to fill the ask
    struct Ask {
        address seller;
        address sellerFundsRecipient;
        address askCurrency;
        uint16 findersFeeBps;
        uint256 askPrice;
    }

    /// @notice Emitted when an ask is created
    /// @param tokenContract The ERC-721 token address of the created ask
    /// @param tokenId The ERC-721 token ID of the created ask
    /// @param ask The metadata of the created ask
    event AskCreated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Emitted when an ask price is updated
    /// @param tokenContract The ERC-721 token address of the updated ask
    /// @param tokenId The ERC-721 token ID of the updated ask
    /// @param ask The metadata of the updated ask
    event AskPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Emitted when an ask is canceled
    /// @param tokenContract The ERC-721 token address of the canceled ask
    /// @param tokenId The ERC-721 token ID of the canceled ask
    /// @param ask The metadata of the canceled ask
    event AskCanceled(address indexed tokenContract, uint256 indexed tokenId, Ask ask);

    /// @notice Emitted when an ask is filled
    /// @param tokenContract The ERC-721 token address of the filled ask
    /// @param tokenId The ERC-721 token ID of the filled ask
    /// @param buyer The buyer address of the filled ask
    /// @param finder The address of finder who referred the ask
    /// @param ask The metadata of the filled ask
    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, address indexed buyer, address finder, Ask ask);

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
        ModuleNamingSupportV1("Asks: v1.1")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,------.
    //        / \            |AsksV1|
    //      Caller           `--+---'
    //        |   createAsk()   |
    //        | ---------------->
    //        |                 |
    //        |                 |
    //        |    ____________________________________________________________
    //        |    ! ALT  /  Ask already exists for this token?                !
    //        |    !_____/      |                                              !
    //        |    !            |----.                                         !
    //        |    !            |    | _cancelAsk(_tokenContract, _tokenId)    !
    //        |    !            |<---'                                         !
    //        |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //        |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //        |                 |
    //        |                 |----.
    //        |                 |    | create ask
    //        |                 |<---'
    //        |                 |
    //        |                 |----.
    //        |                 |    | emit AskCreated()
    //        |                 |<---'
    //      Caller           ,--+---.
    //        ,-.            |AsksV1|
    //        `-'            `------'
    //        /|\
    //         |
    //        / \
    /// @notice Creates the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token to be sold
    /// @param _tokenId The ID of the ERC-721 token to be sold
    /// @param _askPrice The price to fill the ask
    /// @param _askCurrency The address of the ERC-20 token required to fill, or address(0) for ETH
    /// @param _sellerFundsRecipient The address to send funds once the ask is filled
    /// @param _findersFeeBps The bps of the ask price (post-royalties) to be sent to the referrer of the sale
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency,
        address _sellerFundsRecipient,
        uint16 _findersFeeBps
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAsk must be token owner or operator"
        );
        require(erc721TransferHelper.isModuleApproved(msg.sender), "createAsk must approve AsksV1 module");
        require(
            IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createAsk must approve ERC721TransferHelper as operator"
        );
        require(_findersFeeBps <= 10000, "createAsk finders fee bps must be less than or equal to 10000");
        require(_sellerFundsRecipient != address(0), "createAsk must specify _sellerFundsRecipient");

        if (askForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelAsk(_tokenContract, _tokenId);
        }

        askForNFT[_tokenContract][_tokenId] = Ask({
            seller: tokenOwner,
            sellerFundsRecipient: _sellerFundsRecipient,
            askCurrency: _askCurrency,
            findersFeeBps: _findersFeeBps,
            askPrice: _askPrice
        });

        emit AskCreated(_tokenContract, _tokenId, askForNFT[_tokenContract][_tokenId]);
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,------.
    //        / \            |AsksV1|
    //      Caller           `--+---'
    //        |  setAskPrice()  |
    //        | ---------------->
    //        |                 |
    //        |                 |----.
    //        |                 |    | update ask price
    //        |                 |<---'
    //        |                 |
    //        |                 |----.
    //        |                 |    | emit AskPriceUpdated()
    //        |                 |<---'
    //      Caller           ,--+---.
    //        ,-.            |AsksV1|
    //        `-'            `------'
    //        /|\
    //         |
    //        / \
    /// @notice Updates the ask price for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _askPrice The ask price to set
    /// @param _askCurrency The address of the ERC-20 token required to fill, or address(0) for ETH
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        address _askCurrency
    ) external nonReentrant {
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        require(ask.seller == msg.sender, "setAskPrice must be seller");

        ask.askPrice = _askPrice;
        ask.askCurrency = _askCurrency;

        emit AskPriceUpdated(_tokenContract, _tokenId, ask);
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,------.
    //        / \            |AsksV1|
    //      Caller           `--+---'
    //        |   cancelAsk()   |
    //        | ---------------->
    //        |                 |
    //        |                 |----.
    //        |                 |    | emit AskCanceled()
    //        |                 |<---'
    //        |                 |
    //        |                 |----.
    //        |                 |    | delete ask
    //        |                 |<---'
    //      Caller           ,--+---.
    //        ,-.            |AsksV1|
    //        `-'            `------'
    //        /|\
    //         |
    //        / \
    /// @notice Cancels the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external nonReentrant {
        require(askForNFT[_tokenContract][_tokenId].seller != address(0), "cancelAsk ask doesn't exist");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "cancelAsk must be token owner or operator"
        );

        _cancelAsk(_tokenContract, _tokenId);
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,------.                           ,--------------------.
    //        / \            |AsksV1|                           |ERC721TransferHelper|
    //      Caller           `--+---'                           `---------+----------'
    //        |    fillAsk()    |                                         |
    //        | ---------------->                                         |
    //        |                 |                                         |
    //        |                 |----.                                    |
    //        |                 |    | validate received funds            |
    //        |                 |<---'                                    |
    //        |                 |                                         |
    //        |                 |----.                                    |
    //        |                 |    | handle royalty payouts             |
    //        |                 |<---'                                    |
    //        |                 |                                         |
    //        |                 |                                         |
    //        |    _________________________________________________      |
    //        |    ! ALT  /  finders fee configured for this ask?   !     |
    //        |    !_____/      |                                   !     |
    //        |    !            |----.                              !     |
    //        |    !            |    | handle finders fee payout    !     |
    //        |    !            |<---'                              !     |
    //        |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!     |
    //        |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!     |
    //        |                 |                                         |
    //        |                 |----.
    //        |                 |    | handle seller funds recipient payout
    //        |                 |<---'
    //        |                 |                                         |
    //        |                 |              transferFrom()             |
    //        |                 | ---------------------------------------->
    //        |                 |                                         |
    //        |                 |                                         |----.
    //        |                 |                                         |    | transfer NFT from seller to buyer
    //        |                 |                                         |<---'
    //        |                 |                                         |
    //        |                 |----.                                    |
    //        |                 |    | emit ExchangeExecuted()            |
    //        |                 |<---'                                    |
    //        |                 |                                         |
    //        |                 |----.                                    |
    //        |                 |    | emit AskFilled()                   |
    //        |                 |<---'                                    |
    //        |                 |                                         |
    //        |                 |----.                                    |
    //        |                 |    | delete ask from contract           |
    //        |                 |<---'                                    |
    //      Caller           ,--+---.                           ,---------+----------.
    //        ,-.            |AsksV1|                           |ERC721TransferHelper|
    //        `-'            `------'                           `--------------------'
    //        /|\
    //         |
    //        / \
    /// @notice Fills the ask for a given NFT, transferring the ETH/ERC-20 to the seller and NFT to the buyer
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _fillCurrency The address of the ERC-20 token using to fill, or address(0) for ETH
    /// @param _fillAmount The amount to fill the ask
    /// @param _finder The address of the ask referrer
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        address _fillCurrency,
        uint256 _fillAmount,
        address _finder
    ) external payable nonReentrant {
        Ask storage ask = askForNFT[_tokenContract][_tokenId];

        require(ask.seller != address(0), "fillAsk must be active ask");
        require(ask.askCurrency == _fillCurrency, "fillAsk _fillCurrency must match ask currency");
        require(ask.askPrice == _fillAmount, "fillAsk _fillAmount must match ask amount");

        // Ensure ETH/ERC-20 payment from buyer is valid and take custody
        _handleIncomingTransfer(ask.askPrice, ask.askCurrency);

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, ask.askPrice, ask.askCurrency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, ask.askCurrency);

        // Payout optional finder fee
        if (_finder != address(0)) {
            uint256 findersFee = (remainingProfit * ask.findersFeeBps) / 10000;
            _handleOutgoingTransfer(_finder, findersFee, ask.askCurrency, USE_ALL_GAS_FLAG);

            remainingProfit = remainingProfit - findersFee;
        }

        // Transfer remaining ETH/ERC-20 to seller
        _handleOutgoingTransfer(ask.sellerFundsRecipient, remainingProfit, ask.askCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, ask.seller, msg.sender, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: ask.askCurrency, tokenId: 0, amount: ask.askPrice});

        emit ExchangeExecuted(ask.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit AskFilled(_tokenContract, _tokenId, msg.sender, _finder, ask);

        delete askForNFT[_tokenContract][_tokenId];
    }

    /// @dev Deletes canceled and invalid asks
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function _cancelAsk(address _tokenContract, uint256 _tokenId) private {
        emit AskCanceled(_tokenContract, _tokenId, askForNFT[_tokenContract][_tokenId]);

        delete askForNFT[_tokenContract][_tokenId];
    }
}
