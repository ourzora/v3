// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

// ============ Imports ============

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to make an offer on any ERC-721
contract OffersV1 is ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IWETH weth;

    // ============ Mutable Storage ============

    // User to offer IDs
    mapping(address => uint256[]) public userToOffers;
    // NFT (address + id) to offer IDs
    mapping(address => mapping(uint256 => uint256[])) public nftToOffers;
    // User + NFT (address + id) to whether an active offer exists
    mapping(address => mapping(address => mapping(uint256 => bool))) public userHasActiveOffer;
    // Offer ID to offer
    mapping(uint256 => Offer) public offers;

    Counters.Counter offerCounter;

    enum OfferStatus {
        Active,
        Canceled,
        Accepted
    }

    struct Offer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 tokenId;
        uint256 offerPrice;
        OfferStatus status;
    }

    // ============ Events =============

    event OfferCreated(uint256 indexed id, Offer offer);
    event OfferCanceled(uint256 indexed id, Offer offer);
    event OfferUpdated(uint256 indexed id, Offer offer);
    event OfferAccepted(uint256 indexed id, Offer offer);

    // ============ Constructor ============

    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _zoraV1ProtocolMedia,
        address _wethAddress
    ) {
        erc20TransferHelper = ERC20TransferHelper(_erc20TransferHelper);
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
        zoraV1Media = IZoraV1Media(_zoraV1ProtocolMedia);
        zoraV1Market = IZoraV1Market(zoraV1Media.marketContract());
        weth = IWETH(_wethAddress);
    }

    // ============ Public Functions ============

    function createOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerPrice,
        address _offerCurrency
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createOffer cannot make offer on NFT you own");
        require(userHasActiveOffer[msg.sender][_tokenContract][_tokenId] == false, "createOffer must update or cancel existing offer");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        offerCounter.increment();
        uint256 offerId = offerCounter.current();

        offers[offerId] = Offer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenId: _tokenId,
            offerPrice: _offerPrice,
            status: OfferStatus.Active
        });

        userToOffers[msg.sender].push(offerId);
        nftToOffers[_tokenContract][_tokenId].push(offerId);
        userHasActiveOffer[msg.sender][_tokenContract][_tokenId] = true;

        emit OfferCreated(offerId, offers[offerId]);

        return offerId;
    }

    function updatePrice(uint256 _offerId, uint256 _newOffer) external payable nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "updatePrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "updatePrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit OfferUpdated(_offerId, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency);
            offer.offerPrice -= decreaseAmount;

            emit OfferUpdated(_offerId, offer);
        }
    }

    function cancelOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "cancelOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userHasActiveOffer[offer.buyer][offer.tokenContract][offer.tokenId] = false;

        emit OfferCanceled(_offerId, offer);
    }

    function acceptOffer(uint256 _offerId) external nonReentrant {
        Offer storage offer = offers[_offerId];

        require(offer.status == OfferStatus.Active, "acceptOffer must be active offer");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenId), "acceptOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        uint256 remainingProfit = offer.offerPrice;

        if (offer.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(offer);
        } else if (IERC165(offer.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(offer);
        }

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenId);

        offer.status = OfferStatus.Accepted;
        userHasActiveOffer[offer.buyer][offer.tokenContract][offer.tokenId] = false;

        emit OfferAccepted(_offerId, offer);
    }

    // ============ Private Functions ============

    function _handleIncomingTransfer(uint256 _amount, address _currency) private {
        if (_currency == address(0)) {
            require(msg.value >= _amount, "_handleIncomingTransfer msg value less than expected amount");
        } else {
            // We must check the balance that was actually transferred to this contract,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            erc20TransferHelper.safeTransferFrom(_currency, msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            require((beforeBalance + _amount) == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
        }
    }

    function _handleOutgoingTransfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        // Handle ETH payment
        if (_currency == address(0)) {
            require(address(this).balance >= _amount, "_handleOutgoingTransfer insolvent");
            // Here increase the gas limit a reasonable amount above the default, and try
            // to send ETH to the recipient.
            (bool success, ) = _dest.call{value: _amount, gas: 30000}(new bytes(0));

            // If the ETH transfer fails (sigh), wrap the ETH and try send it as WETH.
            if (!success) {
                weth.deposit{value: _amount}();
                IERC20(address(weth)).safeTransfer(_dest, _amount);
            }
        } else {
            IERC20(_currency).safeTransfer(_dest, _amount);
        }
    }

    function _handleZoraPayout(Offer memory offer) private returns (uint256) {
        IZoraV1Market.BidShares memory bidShares = zoraV1Market.bidSharesForToken(offer.tokenId);

        uint256 creatorProfit = zoraV1Market.splitShare(bidShares.creator, offer.offerPrice);
        uint256 prevOwnerProfit = zoraV1Market.splitShare(bidShares.prevOwner, offer.offerPrice);
        uint256 remainingProfit = offer.offerPrice - creatorProfit - prevOwnerProfit;

        // Pay out creator
        if (creatorProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.tokenCreators(offer.tokenId), creatorProfit, offer.offerCurrency);
        }
        // Pay out prev owner
        if (prevOwnerProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.previousTokenOwner(offer.tokenId), prevOwnerProfit, offer.offerCurrency);
        }

        return remainingProfit;
    }

    function _handleEIP2981Payout(Offer memory offer) private returns (uint256) {
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(offer.tokenContract).royaltyInfo(offer.tokenId, offer.offerPrice);

        uint256 remainingProfit = offer.offerPrice - royaltyAmount;

        if (royaltyAmount != 0 && royaltyReceiver != address(0)) {
            _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, offer.offerCurrency);
        }

        return remainingProfit;
    }
}
