// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {OutgoingTransferSupportV1} from "../../../common/OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {CollectionOfferBookV1} from "./CollectionOfferBookV1.sol";

/// @title Collection Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows users to offer ETH for any ERC-721 token in a specified collection
contract CollectionOffersV1 is
    ReentrancyGuard,
    UniversalExchangeEventV1,
    IncomingTransferSupportV1,
    FeePayoutSupportV1,
    ModuleNamingSupportV1,
    CollectionOfferBookV1
{
    /// @notice The finders fee bps configured by the DAO
    uint16 public findersFeeBps;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// ------------ EVENTS ------------

    /// @notice Emitted when a collection offer is created
    /// @param collection The ERC-721 token address of the created offer
    /// @param id The ID of the created offer
    /// @param maker The address of the offer maker
    /// @param amount The amount of the created offer
    event CollectionOfferCreated(address indexed collection, uint256 indexed id, address maker, uint256 amount);

    /// @notice Emitted when a collection offer is updated
    /// @param collection The ERC-721 token address of the updated offer
    /// @param id The ID of the updated offer
    /// @param maker The address of the offer maker
    /// @param amount The amount of the updated offer
    event CollectionOfferUpdated(address indexed collection, uint256 indexed id, address maker, uint256 amount);

    /// @notice Emitted when a collection offer is canceled
    /// @param collection The ERC-721 token address of the canceled offer
    /// @param id The ID of the canceled offer
    /// @param maker The address of the offer maker
    /// @param amount The amount of the canceled offer
    event CollectionOfferCanceled(address indexed collection, uint256 indexed id, address maker, uint256 amount);

    /// @notice Emitted when a collection offer is filled
    /// @param collection The ERC-721 token address of the filled offer
    /// @param tokenId The ERC-721 token ID of the filled offer
    /// @param id The ID of the filled offer
    /// @param taker The address of the taker who filled the offer
    /// @param finder The address of the finder who referred the sale
    event CollectionOfferFilled(address indexed collection, uint256 indexed tokenId, uint256 indexed id, address taker, address finder);

    /// @notice Emitted when the finders fee is updated by the DAO
    /// @param findersFeeBps The bps of the updated finders fee
    event FindersFeeUpdated(uint16 indexed findersFeeBps);

    /// ------------ CONSTRUCTOR ------------

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
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
        ModuleNamingSupportV1("Collection Offers: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
        findersFeeBps = 100;
    }

    /// ------------ MAKER FUNCTIONS ------------

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,------------------.              ,-------------------.
    //     / \            |CollectionOffersV1|              |ERC20TransferHelper|
    //   Caller           `--------+---------'              `---------+---------'
    //     |     createOffer()     |                                  |
    //     | ---------------------->                                  |
    //     |                       |                                  |
    //     |                       |             msg.value            |
    //     |                       | --------------------------------->
    //     |                       |                                  |
    //     |                       |                                  |----.
    //     |                       |                                  |    | transfer ETH into escrow
    //     |                       |                                  |<---'
    //     |                       |                                  |
    //     |                       |----.                             |
    //     |                       |    | _addOffer()                 |
    //     |                       |<---'                             |
    //     |                       |                                  |
    //     |                       |----.
    //     |                       |    | emit CollectionOfferCreated()
    //     |                       |<---'
    //     |                       |                                  |
    //     |           id          |                                  |
    //     | <----------------------                                  |
    //   Caller           ,--------+---------.              ,---------+---------.
    //     ,-.            |CollectionOffersV1|              |ERC20TransferHelper|
    //     `-'            `------------------'              `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Creates an offer for any NFT in a collection
    /// @param _tokenContract The ERC-721 collection address
    /// @return The ID of the created offer
    function createOffer(address _tokenContract) external payable nonReentrant returns (uint256) {
        // Ensure offer is valid and take custody
        _handleIncomingTransfer(msg.value, address(0));

        // Add to collection's offer book
        uint256 offerId = _addOffer(_tokenContract, msg.value, msg.sender);

        emit CollectionOfferCreated(_tokenContract, offerId, msg.sender, msg.value);

        return offerId;
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,------------------.              ,-------------------.
    //     / \            |CollectionOffersV1|              |ERC20TransferHelper|
    //   Caller           `--------+---------'              `---------+---------'
    //     |    setOfferAmount()   |                                  |
    //     | ---------------------->                                  |
    //     |                       |                                  |
    //     |                       |                                  |
    //     |    __________________________________________________________________________
    //     |    ! ALT  /  increase offer?                             |                   !
    //     |    !_____/            |                                  |                   !
    //     |    !                  |   transfer msg.value to escrow   |                   !
    //     |    !                  | --------------------------------->                   !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    ! [decrease offer] |                                  |                   !
    //     |    !                  |      refund decrease amount      |                   !
    //     |    !                  | --------------------------------->                   !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                       |                                  |
    //     |                       |----.                             |
    //     |                       |    | _updateOffer()              |
    //     |                       |<---'                             |
    //     |                       |                                  |
    //     |                       |----.
    //     |                       |    | emit CollectionOfferUpdated()
    //     |                       |<---'
    //   Caller           ,--------+---------.              ,---------+---------.
    //     ,-.            |CollectionOffersV1|              |ERC20TransferHelper|
    //     `-'            `------------------'              `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Updates the amount of a collection offer
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _offerId The ID of the collection offer
    /// @param _amount The new offer amount
    function setOfferAmount(
        address _tokenContract,
        uint32 _offerId,
        uint256 _amount
    ) external payable nonReentrant {
        Offer storage offer = offers[_tokenContract][_offerId];

        require(msg.sender == offer.maker, "setOfferAmount must be maker");
        require(_amount > 0 && _amount != offer.amount, "setOfferAmount _amount cannot be 0 or previous offer");

        uint256 prevAmount = offer.amount;

        if (_amount > prevAmount) {
            unchecked {
                uint256 increaseAmount = _amount - prevAmount;
                _handleIncomingTransfer(increaseAmount, address(0));
                _updateOffer(offer, _tokenContract, _offerId, _amount, true);
            }
        } else {
            unchecked {
                uint256 decreaseAmount = prevAmount - _amount;
                _handleOutgoingTransfer(msg.sender, decreaseAmount, address(0), 50000);
                _updateOffer(offer, _tokenContract, _offerId, _amount, false);
            }
        }

        emit CollectionOfferUpdated(_tokenContract, _offerId, msg.sender, _amount);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,------------------.               ,-------------------.
    //     / \            |CollectionOffersV1|               |ERC20TransferHelper|
    //   Caller           `--------+---------'               `---------+---------'
    //     |     cancelOffer()     |                                   |
    //     | ---------------------->                                   |
    //     |                       |                                   |
    //     |                       |               call()              |
    //     |                       | ---------------------------------->
    //     |                       |                                   |
    //     |                       |                                   |----.
    //     |                       |                                   |    | refund ETH from escrow
    //     |                       |                                   |<---'
    //     |                       |                                   |
    //     |                       |----.
    //     |                       |    | emit CollectionOfferCanceled()
    //     |                       |<---'
    //     |                       |                                   |
    //     |                       |----.                              |
    //     |                       |    | _removeOffer()               |
    //     |                       |<---'                              |
    //   Caller           ,--------+---------.               ,---------+---------.
    //     ,-.            |CollectionOffersV1|               |ERC20TransferHelper|
    //     `-'            `------------------'               `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Cancels and refunds a collection offer
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _offerId The ID of the collection offer
    function cancelOffer(address _tokenContract, uint32 _offerId) external nonReentrant {
        Offer memory offer = offers[_tokenContract][_offerId];

        require(msg.sender == offer.maker, "cancelOffer must be maker");

        // Refund offer
        _handleOutgoingTransfer(msg.sender, offer.amount, address(0), 50000);

        emit CollectionOfferCanceled(_tokenContract, _offerId, msg.sender, offer.amount);

        _removeOffer(_tokenContract, _offerId);
    }

    /// ------------ TAKER FUNCTIONS ------------

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,------------------.             ,--------------------.
    //     / \            |CollectionOffersV1|             |ERC721TransferHelper|
    //   Caller           `--------+---------'             `---------+----------'
    //     |      fillOffer()      |                                 |
    //     | ---------------------->                                 |
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | validate token owner       |
    //     |                       |<---'                            |
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | _getMatchingOffer()        |
    //     |                       |<---'                            |
    //     |                       |                                 |
    //     |                       |                                 |
    //     |    ________________________________________             |
    //     |    ! ALT  /  offer exists satisfying minimum?           |
    //     |    !_____/            |                    !            |
    //     |    !                  |----.               !            |
    //     |    !                  |    | (continue)    !            |
    //     |    !                  |<---'               !            |
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!            |
    //     |    !~[revert]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!            |
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | handle royalty payouts     |
    //     |                       |<---'                            |
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | handle finders fee payout  |
    //     |                       |<---'                            |
    //     |                       |                                 |
    //     |                       |          transferFrom()         |
    //     |                       | -------------------------------->
    //     |                       |                                 |
    //     |                       |                                 |----.
    //     |                       |                                 |    | transfer NFT from taker to maker
    //     |                       |                                 |<---'
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | emit ExchangeExecuted()    |
    //     |                       |<---'                            |
    //     |                       |                                 |
    //     |                       |----.
    //     |                       |    | emit CollectionOfferFilled()
    //     |                       |<---'
    //     |                       |                                 |
    //     |                       |----.                            |
    //     |                       |    | _removeOffer()             |
    //     |                       |<---'                            |
    //   Caller           ,--------+---------.             ,---------+----------.
    //     ,-.            |CollectionOffersV1|             |ERC721TransferHelper|
    //     `-'            `------------------'             `--------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Fills the highest collection offer above a specified minimum, if exists
    /// @param _tokenContract The address of the ERC-721 collection
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _minAmount The minimum amount willing to accept
    /// @param _finder The address of the offer referrer
    function fillOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _minAmount,
        address _finder
    ) external nonReentrant {
        require(msg.sender == IERC721(_tokenContract).ownerOf(_tokenId), "fillOffer must own specified token");

        // Get matching offer (if exists)
        uint256 offerId = _getMatchingOffer(_tokenContract, _minAmount);
        require(offerId != 0, "fillOffer offer satisfying _minAmount not found");

        Offer memory offer = offers[_tokenContract][offerId];

        // Ensure royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, offer.amount, address(0), 300000);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Payout optional finder fee
        if (_finder != address(0)) {
            uint256 findersFee;
            // Calculate payout
            findersFee = (remainingProfit * findersFeeBps) / 10000;
            // Transfer to finder
            _handleOutgoingTransfer(_finder, findersFee, address(0), 50000);
            // Update remaining profit
            remainingProfit -= findersFee;
        }

        // Transfer remaining ETH to taker
        _handleOutgoingTransfer(msg.sender, remainingProfit, address(0), 50000);

        // Transfer NFT to maker
        erc721TransferHelper.transferFrom(_tokenContract, msg.sender, offer.maker, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: address(0), tokenId: 0, amount: offer.amount});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});

        emit ExchangeExecuted(offer.maker, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit CollectionOfferFilled(_tokenContract, _tokenId, offerId, msg.sender, _finder);

        _removeOffer(_tokenContract, offerId);
    }

    /// ------------ DAO FUNCTIONS ------------

    //     ,-.
    //     `-'
    //     /|\
    //      |              ,------------------.
    //     / \             |CollectionOffersV1|
    //   zoraDAO           `--------+---------'
    //      |   setFindersFee()     |
    //      |---------------------->|
    //      |                       |
    //      |                       |----.
    //      |                       |    | update finders fee
    //      |                       |<---'
    //      |                       |
    //      |                       |----.
    //      |                       |    | emit FindersFeeUpdated()
    //      |                       |<---'
    //   zoraDAO           ,--------+---------.
    //     ,-.             |CollectionOffersV1|
    //     `-'             `------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Updates the finders fee for collection offers
    /// @param _findersFeeBps The new finders fee bps
    function setFindersFee(uint16 _findersFeeBps) external nonReentrant {
        require(msg.sender == registrar, "setFindersFee only registrar");
        require(_findersFeeBps <= 10000, "setFindersFee bps must be <= 10000");

        findersFeeBps = _findersFeeBps;

        emit FindersFeeUpdated(_findersFeeBps);
    }
}
