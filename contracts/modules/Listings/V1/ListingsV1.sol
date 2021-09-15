// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";

contract ListingsV1 is ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;
    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IWETH weth;

    Counters.Counter listingCounter;

    // listing by user
    mapping(address => uint256[]) public listingsForUser;

    // listing by NFT
    // NFT address => NFT ID => listing ID
    mapping(address => mapping(uint256 => uint256)) public listingForNFT;

    // listing by ID
    mapping(uint256 => Listing) public listings;

    enum ListingStatus {
        Active,
        Canceled,
        Filled
    }

    struct Listing {
        address tokenContract;
        address seller;
        address fundsRecipient;
        address listingCurrency;
        uint256 tokenId;
        uint256 listingPrice;
        ListingStatus status;
    }

    event ListingCreated(uint256 indexed id, Listing listing);

    event ListingCanceled(uint256 indexed id, Listing listing);

    event ListingFilled(uint256 indexed id, address buyer, Listing listing);

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

    function createListing(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _listingPrice,
        address _listingCurrency,
        address _fundsRecipient
    ) external nonReentrant returns (uint256) {
        require(_fundsRecipient != address(0), "createListing must specify fundsRecipient");

        // Create a listing
        listingCounter.increment();
        uint256 listingId = listingCounter.current();
        listings[listingId] = Listing({
            tokenContract: _tokenContract,
            seller: msg.sender,
            fundsRecipient: _fundsRecipient,
            listingCurrency: _listingCurrency,
            tokenId: _tokenId,
            listingPrice: _listingPrice,
            status: ListingStatus.Active
        });

        // Register listing lookup helpers
        listingsForUser[msg.sender].push(listingId);
        listingForNFT[_tokenContract][_tokenId] = listingId;

        emit ListingCreated(listingId, listings[listingId]);

        return listingId;
    }

    function cancelListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];

        require(
            listing.seller == msg.sender || IERC721(listing.tokenContract).ownerOf(listing.tokenId) != listing.seller,
            "cancelListing must be seller or invalid listing"
        );
        require(listing.status == ListingStatus.Active, "cancelListing must be active listing");

        // Set listing status to cancelled
        listing.status = ListingStatus.Canceled;

        emit ListingCanceled(_listingId, listing);
    }

    function fillListing(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];

        require(listing.seller != address(0), "fillListing listing does not exist");
        require(listing.status == ListingStatus.Active, "fillListing must be active listing");

        // Ensure payment is valid and take custody of payment
        _handleIncomingTransfer(listing.listingPrice, listing.listingCurrency);

        // Payout respective parties, ensuring royalties are honored
        if (listing.tokenContract == address(zoraV1Media)) {
            _handleZoraPayout(listing);
        } else if (IERC165(listing.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            _handleEIP2981Payout(listing);
        } else {
            _handleOutgoingTransfer(listing.fundsRecipient, listing.listingPrice, listing.listingCurrency);
        }

        // Transfer NFT to auction winner
        erc721TransferHelper.transferFrom(listing.tokenContract, listing.seller, msg.sender, listing.tokenId);

        listing.status = ListingStatus.Filled;

        emit ListingFilled(_listingId, msg.sender, listing);
    }

    function _handleZoraPayout(Listing memory listing) private {
        IZoraV1Market.BidShares memory bidShares = zoraV1Market.bidSharesForToken(listing.tokenId);

        uint256 creatorProfit = zoraV1Market.splitShare(bidShares.creator, listing.listingPrice);
        uint256 prevOwnerProfit = zoraV1Market.splitShare(bidShares.prevOwner, listing.listingPrice);
        uint256 remainingProfit = listing.listingPrice.sub(creatorProfit).sub(prevOwnerProfit);

        // Pay out creator
        if (creatorProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.tokenCreators(listing.tokenId), creatorProfit, listing.listingCurrency);
        }
        // Pay out prev owner
        if (prevOwnerProfit != 0) {
            _handleOutgoingTransfer(zoraV1Media.previousTokenOwner(listing.tokenId), prevOwnerProfit, listing.listingCurrency);
        }
        // Pay out funds recipient
        if (remainingProfit != 0) {
            _handleOutgoingTransfer(listing.fundsRecipient, remainingProfit, listing.listingCurrency);
        }
    }

    function _handleEIP2981Payout(Listing memory listing) private {
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(listing.tokenContract).royaltyInfo(listing.tokenId, listing.listingPrice);

        uint256 remainingProfit = listing.listingPrice.sub(royaltyAmount);

        if (royaltyAmount != 0 && royaltyReceiver != address(0)) {
            _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, listing.listingCurrency);
        }

        if (remainingProfit != 0) {
            _handleOutgoingTransfer(listing.fundsRecipient, remainingProfit, listing.listingCurrency);
        }
    }

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
            require(beforeBalance.add(_amount) == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
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
