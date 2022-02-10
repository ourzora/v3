// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows users to make ETH/ERC-20 offers for any ERC-721 token
contract OffersV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The total number of offers made
    uint256 public offerCount;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The metadata of an offer
    /// @param maker The address of the user who made the offer
    /// @param currency The address of the ERC-20 offered, or address(0) for ETH
    /// @param findersFeeBps The fee to the referrer of the offer
    /// @param amount The amount of ETH/ERC-20 tokens offered
    struct Offer {
        address maker;
        address currency;
        uint16 findersFeeBps;
        uint256 amount;
    }

    /// ------------ STORAGE ------------

    /// @notice The metadata for a given offer
    /// @dev ERC-721 token address => ERC-721 token ID => Offer ID => Offer
    mapping(address => mapping(uint256 => mapping(uint256 => Offer))) public offers;

    /// @notice The offers for a given NFT
    /// @dev ERC-721 token address => ERC-721 token ID => Offer IDs
    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    /// ------------ EVENTS ------------

    /// @notice Emitted when an offer is created
    /// @param tokenContract The ERC-721 token address of the created offer
    /// @param tokenId The ERC-721 token ID of the created offer
    /// @param id The ID of the created offer
    /// @param offer The metadata of the created offer
    event OfferCreated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is updated
    /// @param tokenContract The ERC-721 token address of the updated offer
    /// @param tokenId The ERC-721 token ID of the updated offer
    /// @param id The ID of the updated offer
    /// @param offer The metadata of the updated offer
    event OfferUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is canceled
    /// @param tokenContract The ERC-721 token address of the canceled offer
    /// @param tokenId The ERC-721 token ID of the canceled offer
    /// @param id The ID of the canceled offer
    /// @param offer The metadata of the canceled offer
    event OfferCanceled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, Offer offer);

    /// @notice Emitted when an offer is filled
    /// @param tokenContract The ERC-721 token address of the filled offer
    /// @param tokenId The ERC-721 token ID of the filled offer
    /// @param id The ID of the filled offer
    /// @param taker The address of the taker who filled the offer
    /// @param finder The address of the finder who referred the offer
    /// @param offer The metadata of the filled offer
    event OfferFilled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed id, address taker, address finder, Offer offer);

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
        ModuleNamingSupportV1("Offers: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// ------------ MAKER FUNCTIONS ------------

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------.               ,-------------------.
    //     / \            |OffersV1|               |ERC20TransferHelper|
    //   Caller           `---+----'               `---------+---------'
    //     |   createOffer()  |                              |
    //     | ----------------->                              |
    //     |                  |                              |
    //     |                  |        transferFrom()        |
    //     |                  | ----------------------------->
    //     |                  |                              |
    //     |                  |                              |----.
    //     |                  |                              |    | transfer tokens into escrow
    //     |                  |                              |<---'
    //     |                  |                              |
    //     |                  |----.                         |
    //     |                  |    | ++offerCount            |
    //     |                  |<---'                         |
    //     |                  |                              |
    //     |                  |----.                         |
    //     |                  |    | create offer            |
    //     |                  |<---'                         |
    //     |                  |                              |
    //     |                  |----.
    //     |                  |    | offersFor[NFT].append(id)
    //     |                  |<---'
    //     |                  |                              |
    //     |                  |----.                         |
    //     |                  |    | emit OfferCreated()     |
    //     |                  |<---'                         |
    //     |                  |                              |
    //     |        id        |                              |
    //     | <-----------------                              |
    //   Caller           ,---+----.               ,---------+---------.
    //     ,-.            |OffersV1|               |ERC20TransferHelper|
    //     `-'            `--------'               `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Creates an offer for an NFT
    /// @param _tokenContract The address of the desired ERC-721 token
    /// @param _tokenId The ID of the desired ERC-721 token
    /// @param _currency The address of the ERC-20 token offering, or address(0) for ETH
    /// @param _amount The amount offering
    /// @param _findersFeeBps The bps of the amount (post-royalties) to send to a referrer of the sale
    /// @return The ID of the created offer
    function createOffer(
        address _tokenContract,
        uint256 _tokenId,
        address _currency,
        uint256 _amount,
        uint16 _findersFeeBps
    ) external payable nonReentrant returns (uint256) {
        require(_findersFeeBps <= 10000, "createOffer finders fee bps must be less than or equal to 10000");

        // Validate offer and take custody
        _handleIncomingTransfer(_amount, _currency);

        // "the sun will devour the earth before it could ever overflow" - @transmissions11
        // offerCount++ --> unchecked { offerCount++ }

        // "Although the increment part is cheaper with unchecked, the opcodes after become more expensive for some reason" - @joshieDo
        // unchecked { offerCount++ } --> offerCount++

        // "Earlier today while reviewing c4rena findings I learned that doing ++offerCount would save 5 gas per increment here" - @devtooligan
        // offerCount++ --> ++offerCount

        // TLDR;           unchecked       checked
        // non-optimized   130,037 gas  <  130,149 gas
        // optimized       127,932 gas  >  *127,298 gas*

        ++offerCount;

        offers[_tokenContract][_tokenId][offerCount] = Offer({
            maker: msg.sender,
            currency: _currency,
            findersFeeBps: _findersFeeBps,
            amount: _amount
        });

        offersForNFT[_tokenContract][_tokenId].push(offerCount);

        emit OfferCreated(_tokenContract, _tokenId, offerCount, offers[_tokenContract][_tokenId][offerCount]);

        return offerCount;
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------.                     ,-------------------.
    //     / \            |OffersV1|                     |ERC20TransferHelper|
    //   Caller           `---+----'                     `---------+---------'
    //     | setOfferAmount() |                                    |
    //     | ----------------->                                    |
    //     |                  |                                    |
    //     |                  |                                    |
    //     |    _______________________________________________________________________
    //     |    ! ALT  /  same token?                              |                   !
    //     |    !_____/       |                                    |                   !
    //     |    !             | retrieve increase / refund decrease|                   !
    //     |    !             | ----------------------------------->                   !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    ! [different token]                                |                   !
    //     |    !             |        refund previous offer       |                   !
    //     |    !             | ----------------------------------->                   !
    //     |    !             |                                    |                   !
    //     |    !             |         retrieve new offer         |                   !
    //     |    !             | ----------------------------------->                   !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                  |                                    |
    //     |                  |----.                               |
    //     |                  |    | emit OfferUpdated()           |
    //     |                  |<---'                               |
    //   Caller           ,---+----.                     ,---------+---------.
    //     ,-.            |OffersV1|                     |ERC20TransferHelper|
    //     `-'            `--------'                     `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Updates the given offer for an NFT
    /// @param _tokenContract The address of the offer ERC-721 token
    /// @param _tokenId The ID of the offer ERC-721 token
    /// @param _offerId The ID of the offer
    /// @param _currency The address of the ERC-20 token offering, or address(0) for ETH
    /// @param _amount The new amount offering
    function setOfferAmount(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _currency,
        uint256 _amount
    ) external payable nonReentrant {
        Offer storage offer = offers[_tokenContract][_tokenId][_offerId];

        require(offer.maker == msg.sender, "setOfferAmount must be maker");

        // If same currency --
        if (_currency == offer.currency) {
            // Get initial amount
            uint256 prevAmount = offer.amount;
            // Ensure valid update
            require(_amount > 0 && _amount != prevAmount, "setOfferAmount invalid _amount");

            // If offer increase --
            if (_amount > prevAmount) {
                unchecked {
                    // Get delta
                    uint256 increaseAmount = _amount - prevAmount;
                    // Custody increase
                    _handleIncomingTransfer(increaseAmount, offer.currency);
                    // Update storage
                    offer.amount += increaseAmount;
                }
                // Else offer decrease --
            } else {
                unchecked {
                    // Get delta
                    uint256 decreaseAmount = prevAmount - _amount;
                    // Refund difference
                    _handleOutgoingTransfer(offer.maker, decreaseAmount, offer.currency, USE_ALL_GAS_FLAG);
                    // Update storage
                    offer.amount -= decreaseAmount;
                }
            }
            // Else other currency --
        } else {
            // Refund previous offer
            _handleOutgoingTransfer(offer.maker, offer.amount, offer.currency, USE_ALL_GAS_FLAG);
            // Custody new offer
            _handleIncomingTransfer(_amount, _currency);

            // Update storage
            offer.currency = _currency;
            offer.amount = _amount;
        }

        emit OfferUpdated(_tokenContract, _tokenId, _offerId, offer);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------.          ,-------------------.
    //     / \            |OffersV1|          |ERC20TransferHelper|
    //   Caller           `---+----'          `---------+---------'
    //     |   cancelOffer()  |                         |
    //     | ----------------->                         |
    //     |                  |                         |
    //     |                  |      transferFrom()     |
    //     |                  | ------------------------>
    //     |                  |                         |
    //     |                  |                         |----.
    //     |                  |                         |    | refund tokens from escrow
    //     |                  |                         |<---'
    //     |                  |                         |
    //     |                  |----.
    //     |                  |    | emit OfferCanceled()
    //     |                  |<---'
    //     |                  |                         |
    //     |                  |----.                    |
    //     |                  |    | delete offer       |
    //     |                  |<---'                    |
    //   Caller           ,---+----.          ,---------+---------.
    //     ,-.            |OffersV1|          |ERC20TransferHelper|
    //     `-'            `--------'          `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Cancels and refunds the given offer for an NFT
    /// @param _tokenContract The ERC-721 token address of the offer
    /// @param _tokenId The ERC-721 token ID of the offer
    /// @param _offerId The ID of the offer
    function cancelOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external nonReentrant {
        Offer memory offer = offers[_tokenContract][_tokenId][_offerId];

        require(offer.maker == msg.sender, "cancelOffer must be maker");

        // Refund offer
        _handleOutgoingTransfer(offer.maker, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        emit OfferCanceled(_tokenContract, _tokenId, _offerId, offer);

        delete offers[_tokenContract][_tokenId][_offerId];
    }

    /// ------------ TAKER FUNCTIONS ------------

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,--------.                ,--------------------.
    //     / \            |OffersV1|                |ERC721TransferHelper|
    //   Caller           `---+----'                `---------+----------'
    //     |    fillOffer()   |                               |
    //     | ----------------->                               |
    //     |                  |                               |
    //     |                  |----.                          |
    //     |                  |    | validate token owner     |
    //     |                  |<---'                          |
    //     |                  |                               |
    //     |                  |----.                          |
    //     |                  |    | handle royalty payouts   |
    //     |                  |<---'                          |
    //     |                  |                               |
    //     |                  |                               |
    //     |    __________________________________________________
    //     |    ! ALT  /  finders fee configured for this offer?  !
    //     |    !_____/       |                               |   !
    //     |    !             |----.                          |   !
    //     |    !             |    | handle finders fee payout|   !
    //     |    !             |<---'                          |   !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                  |                               |
    //     |                  |         transferFrom()        |
    //     |                  | ------------------------------>
    //     |                  |                               |
    //     |                  |                               |----.
    //     |                  |                               |    | transfer NFT from taker to maker
    //     |                  |                               |<---'
    //     |                  |                               |
    //     |                  |----.                          |
    //     |                  |    | emit ExchangeExecuted()  |
    //     |                  |<---'                          |
    //     |                  |                               |
    //     |                  |----.                          |
    //     |                  |    | emit OfferFilled()       |
    //     |                  |<---'                          |
    //     |                  |                               |
    //     |                  |----.
    //     |                  |    | delete offer from contract
    //     |                  |<---'
    //   Caller           ,---+----.                ,---------+----------.
    //     ,-.            |OffersV1|                |ERC721TransferHelper|
    //     `-'            `--------'                `--------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Fills a given offer for an owned NFT, in exchange for ETH/ERC-20 tokens
    /// @param _tokenContract The address of the ERC-721 token to transfer
    /// @param _tokenId The ID of the ERC-721 token to transfer
    /// @param _offerId The ID of the offer to fill
    /// @param _currency The address of the ERC-20 to take, or address(0) for ETH
    /// @param _amount The amount to take
    /// @param _finder The address of the offer referrer
    function fillOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _currency,
        uint256 _amount,
        address _finder
    ) external nonReentrant {
        Offer memory offer = offers[_tokenContract][_tokenId][_offerId];

        require(offer.maker != address(0), "fillOffer must be active offer");
        require(IERC721(_tokenContract).ownerOf(_tokenId) == msg.sender, "fillOffer must be token owner");
        require(offer.currency == _currency && offer.amount == _amount, "fillOffer _currency & _amount must match offer");

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, offer.amount, offer.currency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, offer.currency);

        // Payout optional finders fee
        if (_finder != address(0)) {
            uint256 findersFee = (remainingProfit * offer.findersFeeBps) / 10000;
            _handleOutgoingTransfer(_finder, findersFee, offer.currency, USE_ALL_GAS_FLAG);

            remainingProfit -= findersFee;
        }

        // Transfer remaining ETH/ERC-20 tokens to offer taker
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.currency, USE_ALL_GAS_FLAG);

        // Transfer NFT to offer maker
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.maker, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: offer.currency, tokenId: 0, amount: offer.amount});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});

        emit ExchangeExecuted(offer.maker, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit OfferFilled(_tokenContract, _tokenId, _offerId, msg.sender, _finder, offer);

        delete offers[_tokenContract][_tokenId][_offerId];
    }
}
