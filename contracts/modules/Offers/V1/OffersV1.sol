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

contract OffersV1 is ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IWETH weth;

    Counters.Counter offerCounter;

    // ============ Mutable Storage ============

    // Offers by user
    mapping(address => uint256[]) public userToOffers;

    //
    // User => NFT address => NFT ID => bool
    mapping(address => mapping(address => mapping(uint256 => bool))) public userToActiveOffer;

    // Offers by NFT
    // NFT address => NFT ID => Offer IDs
    mapping(address => mapping(uint256 => uint256[])) public nftToOffers;

    // Offer by id
    mapping(uint256 => Offer) public offers;

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

    // ============ Events ============

    event OfferCreated(uint256 indexed offerId, Offer offer);
    event OfferIncreased(uint256 indexed offerId, uint256 amount, Offer offer);
    event OfferCanceled(uint256 indexed offerId, Offer offer);
    event OfferAccepted(uint256 indexed offerId, address buyer, Offer offer);

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
        require(IERC721(_tokenContract).ownerOf(_tokenId) != msg.sender, "createOffer caller cannot make offer on token already owned");
        require(
            userToActiveOffer[msg.sender][_tokenContract][_tokenId] == false,
            "createOffer cannot make another offer for this NFT ... update or cancel the existing active offer!"
        );

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
        userToActiveOffer[msg.sender][_tokenContract][_tokenId] = true;

        emit OfferCreated(offerId, offers[offerId]);

        return offerId;
    }

    function increaseOffer(uint256 _offerId, uint256 _amount) external payable {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender, "increaseOffer must be buyer");
        require(offer.status == OfferStatus.Active, "increaseOffer must be active offer");
        require(msg.value == _amount, "increaseOffer must transfer equal amount of funds specified");

        // Ensure increased offer payment is valid and take custody of payment
        _handleIncomingTransfer(_amount, offer.offerCurrency);

        offer.offerPrice += _amount;

        emit OfferIncreased(_offerId, _amount, offer);
    }

    function cancelOffer(uint256 _offerId) external {
        Offer storage offer = offers[_offerId];

        require(offer.buyer == msg.sender || IERC721(offer.tokenContract).ownerOf(offer.tokenId) != offer.buyer, "cancelOffer must be buyer or invalid offer");
        require(offer.status == OfferStatus.Active, "cancelOffer must be active offer");

        // Refund
        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userToActiveOffer[offer.buyer][offer.tokenContract][offer.tokenId] = false;

        emit OfferCanceled(_offerId, offer);
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
}
