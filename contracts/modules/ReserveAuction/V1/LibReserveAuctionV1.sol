// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {CollectionRoyaltyRegistryV1} from "../../CollectionRoyaltyRegistry/V1/CollectionRoyaltyRegistryV1.sol";

/// @title Reserve Auction V1 Library
/// @author tbtstl <t@zora.co>
/// @notice This library manages the creation and execution of reserve auctions for any ERC-721 token
library LibReserveAuctionV1 {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeERC20 for IERC20;

    struct ReserveAuctionStorage {
        bool initialized;
        address erc20TransferHelper;
        address erc721TransferHelper;
        address royaltyRegistry;
        address zoraV1ProtocolMedia;
        address zoraV1ProtocolMarket;
        address wethAddress;
        Counters.Counter auctionIdTracker;
        uint256 version;
        mapping(uint256 => Auction) auctions;
        mapping(address => mapping(uint256 => uint256)) nftToAuctionId;
    }

    bytes4 constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    /// @notice The minimum percentage difference between the last bid amount and the current bid.
    uint8 constant minBidIncrementPercentage = 10; // 10%

    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint256 constant timeBuffer = 15 * 60; // 15 minutes

    struct Auction {
        // ID for the ERC721 token
        uint256 tokenId;
        // Address for the ERC721 contract
        address tokenContract;
        // The current highest bid amount
        uint256 amount;
        // The length of time to run the auction for, after the first bid was made
        uint256 duration;
        // The time of the first bid
        uint256 firstBidTime;
        // The minimum price of the first bid
        uint256 reservePrice;
        // The sale percentage to send to the host
        uint8 listingFeePercentage;
        // The sale percentage to send to the winning bid finder
        uint8 findersFeePercentage;
        // The address that should receive the funds once the NFT is sold.
        address tokenOwner;
        // The address of the current highest bid
        address payable bidder;
        // The address of the auction's host.
        address payable host;
        // The address of the recipient of the auction's highest bid
        address payable fundsRecipient;
        // The address of the current bid's finder
        address payable finder;
        // The address of the ERC-20 currency to run the auction with.
        // If set to 0x0, the auction will be run in ETH
        address auctionCurrency;
    }

    event AuctionCreated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 duration,
        uint256 reservePrice,
        address tokenOwner,
        address host,
        address fundsRecipient,
        uint8 listingFeePercentage,
        address auctionCurrency
    );

    event AuctionReservePriceUpdated(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, uint256 reservePrice);

    event AuctionBid(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address sender,
        address finder,
        uint256 value,
        bool firstBid,
        bool extended
    );

    event AuctionDurationExtended(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, uint256 duration);

    event AuctionEnded(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address host,
        address winner,
        address fundsRecipient,
        uint256 amount,
        uint256 finderFee,
        uint256 listingFee,
        address auctionCurrency
    );

    event AuctionCanceled(uint256 indexed auctionId, uint256 indexed tokenId, address indexed tokenContract, address tokenOwner);

    modifier auctionExists(ReserveAuctionStorage storage _self, uint256 auctionId) {
        require(_exists(_self, auctionId), "auctionExists auction doesn't exist");
        _;
    }

    /// @notice Initialize a storage slot for the library to run in
    /// @param _self The storage slot to use
    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _zoraV1ProtocolMedia The ZORA NFT Protocol Media Contract address
    /// @param _royaltyRegistry The ZORA Collection Royalty Registry address
    /// @param _wethAddress WETH token address
    function init(
        ReserveAuctionStorage storage _self,
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _zoraV1ProtocolMedia,
        address _royaltyRegistry,
        address _wethAddress
    ) internal {
        require(_self.initialized != true, "init already initialized");
        _self.zoraV1ProtocolMedia = _zoraV1ProtocolMedia;
        _self.zoraV1ProtocolMarket = IZoraV1Media(_zoraV1ProtocolMedia).marketContract();
        _self.wethAddress = _wethAddress;
        _self.erc20TransferHelper = _erc20TransferHelper;
        _self.erc721TransferHelper = _erc721TransferHelper;
        _self.royaltyRegistry = _royaltyRegistry;
        _self.initialized = true;
        // Ensure auction IDs start at 1 so we can reserve 0 for "nonexistant"
        _self.auctionIdTracker.increment();
    }

    /// @notice Create an auction.
    /// @dev Store the auction details in the auctions mapping and emit an AuctionCreated event.
    /// @param _self Storage slot
    /// @param _tokenId The ID of the ERC-721 token being listed for sale
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _duration The amount of time the auction should run for after the initial bid is placed
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _host The host of the sale, who can receive _listingFeePercentage of the sale price
    /// @param _fundsRecipient The address to send funds to once the token is sold
    /// @param _listingFeePercentage The percentage of the sale amount to be sent to the host
    /// @param _findersFeePercentage The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @return The ID of the created auction
    function createAuction(
        ReserveAuctionStorage storage _self,
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _host,
        address payable _fundsRecipient,
        uint8 _listingFeePercentage,
        uint8 _findersFeePercentage,
        address _auctionCurrency
    ) internal returns (uint256) {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(_listingFeePercentage.add(_findersFeePercentage) < 100, "createAuction listingFeePercentage plus findersFeePercentage must be less than 100");
        require(_fundsRecipient != address(0), "createAuction fundsRecipient cannot be 0 address");
        require(
            tokenOwner == msg.sender ||
                IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender) ||
                IERC721(_tokenContract).getApproved(_tokenId) == msg.sender,
            "createAuction caller must be approved or owner for token id"
        );
        uint256 auctionId = _self.auctionIdTracker.current();

        // If another auction already exists for this nft, cancel it
        if (_self.nftToAuctionId[_tokenContract][_tokenId] != 0) {
            cancelAuction(_self, _self.nftToAuctionId[_tokenContract][_tokenId]);
        }

        _self.auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            amount: 0,
            duration: _duration,
            firstBidTime: 0,
            reservePrice: _reservePrice,
            listingFeePercentage: _listingFeePercentage,
            findersFeePercentage: _findersFeePercentage,
            tokenOwner: tokenOwner,
            bidder: payable(address(0)),
            host: _host,
            fundsRecipient: _fundsRecipient,
            finder: payable(address(0)),
            auctionCurrency: _auctionCurrency
        });
        _self.nftToAuctionId[_tokenContract][_tokenId] = auctionId;

        _self.auctionIdTracker.increment();

        emit AuctionCreated(
            auctionId,
            _tokenId,
            _tokenContract,
            _duration,
            _reservePrice,
            tokenOwner,
            _host,
            _fundsRecipient,
            _listingFeePercentage,
            _auctionCurrency
        );

        return auctionId;
    }

    /// @notice Update the reserve price for a given auction
    /// @param _self Storage slot
    /// @param _auctionId The ID for the auction
    /// @param _reservePrice The new reserve price for the auction
    function setAuctionReservePrice(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        uint256 _reservePrice
    ) internal auctionExists(_self, _auctionId) {
        Auction storage auction = _self.auctions[_auctionId];
        require(msg.sender == auction.tokenOwner, "setAuctionReservePrice must be token owner");
        require(auction.firstBidTime == 0, "setAuctionReservePrice auction has already started");

        auction.reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_auctionId, auction.tokenId, auction.tokenContract, _reservePrice);
    }

    /// @notice Places a bid on the auction, holding the bids in escrow and refunding any previous bids
    /// @param _self The storage slot
    /// @param _auctionId The ID of the auction
    /// @param _amount The bid amount to be transferred
    /// @param _finder The address of the referrer for this bid
    function createBid(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        uint256 _amount,
        address _finder
    ) internal auctionExists(_self, _auctionId) {
        Auction storage auction = _self.auctions[_auctionId];
        address payable lastBidder = auction.bidder;
        require(auction.firstBidTime == 0 || block.timestamp < auction.firstBidTime.add(auction.duration), "createBid auction expired");
        require(_amount >= auction.reservePrice, "createBid must send at least reservePrice");
        require(
            _amount >= auction.amount.add(auction.amount.mul(minBidIncrementPercentage).div(100)),
            "createBid must send more than the last bid by minBidIncrementPercentage amount"
        );
        require(_finder != address(0), "createBid _finder must not be 0 address");

        // For Zora V1 Protocol, ensure that the bid is valid for the current bidShare configuration
        if (auction.tokenContract == _self.zoraV1ProtocolMedia) {
            require(IZoraV1Market(_self.zoraV1ProtocolMarket).isValidBid(auction.tokenId, _amount), "createBid bid invalid for share splitting");
        }

        // If this is the first valid bid, we should set the starting time now and take the NFT into escrow
        // If it's not, then we should refund the last bidder
        if (auction.firstBidTime == 0) {
            auction.firstBidTime = block.timestamp;
            ERC721TransferHelper(_self.erc721TransferHelper).transferFrom(auction.tokenContract, auction.tokenOwner, address(this), auction.tokenId);
        } else if (lastBidder != address(0)) {
            _handleOutgoingTransfer(_self, lastBidder, auction.amount, auction.auctionCurrency);
        }

        _handleIncomingTransfer(_self, _amount, auction.auctionCurrency);

        auction.amount = _amount;
        auction.bidder = payable(msg.sender);
        auction.finder = payable(_finder);

        bool extended = false;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if (auction.firstBidTime.add(auction.duration).sub(block.timestamp) < timeBuffer) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionId].firstBidTime.add(auctions[auctionId].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionId].duration.add(timeToAdd);
            uint256 oldDuration = auction.duration;
            auction.duration = oldDuration.add(timeBuffer.sub(auction.firstBidTime.add(oldDuration).sub(block.timestamp)));
            extended = true;
        }

        emit AuctionBid(
            _auctionId,
            auction.tokenId,
            auction.tokenContract,
            msg.sender,
            _finder,
            _amount,
            lastBidder == address(0), // firstBid boolean
            extended
        );

        if (extended) {
            emit AuctionDurationExtended(_auctionId, auction.tokenId, auction.tokenContract, auction.duration);
        }
    }

    /// @notice End an auction, paying out respective parties and transferring the token to the winning bidder
    /// @param _self The storage slot
    /// @param _auctionId The ID of  the auction
    function settleAuction(ReserveAuctionStorage storage _self, uint256 _auctionId) internal auctionExists(_self, _auctionId) {
        Auction storage auction = _self.auctions[_auctionId];
        require(auction.firstBidTime != 0, "settleAuction auction hasn't begun");
        require(block.timestamp >= auction.firstBidTime.add(auction.duration), "settleAuction auction hasn't completed");

        uint256 remainingProfit = auction.amount;
        if (auction.tokenContract == _self.zoraV1ProtocolMedia) {
            remainingProfit = _handleZoraAuctionPayout(_self, _auctionId);
        } else if (IERC165(auction.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981AuctionPayout(_self, _auctionId);
        } else {
            remainingProfit = _handleRoyaltyRegistryPayout(_self, _auctionId);
        }

        uint256 hostProfit;
        uint256 finderProfit = remainingProfit.mul(auction.findersFeePercentage).div(100);
        if (auction.host != address(0)) {
            hostProfit = remainingProfit.mul(auction.listingFeePercentage).div(100);
            _handleOutgoingTransfer(_self, auction.host, hostProfit, auction.auctionCurrency);
        }
        remainingProfit = remainingProfit.sub(hostProfit).sub(finderProfit);

        _handleOutgoingTransfer(_self, auction.finder, finderProfit, auction.auctionCurrency);
        _handleOutgoingTransfer(_self, auction.fundsRecipient, remainingProfit, auction.auctionCurrency);

        // Transfer NFT to winner
        IERC721(auction.tokenContract).transferFrom(address(this), auction.bidder, auction.tokenId);

        emit AuctionEnded(
            _auctionId,
            auction.tokenId,
            auction.tokenContract,
            auction.host,
            auction.bidder,
            auction.fundsRecipient,
            remainingProfit,
            hostProfit,
            finderProfit,
            auction.auctionCurrency
        );

        delete _self.auctions[_auctionId];
    }

    /// @notice Cancel an auction
    /// @param _self The storage slot
    /// @param _auctionId The ID of the auction
    function cancelAuction(ReserveAuctionStorage storage _self, uint256 _auctionId) internal auctionExists(_self, _auctionId) {
        Auction storage auction = _self.auctions[_auctionId];

        require(auction.firstBidTime == 0, "cancelAuction auction already started");
        // If the auction creator has already transferred the token elsewhere, let anyone cancel the auction, since it is no longer valid.
        // Otherwise, only allow the token owner to cancel the auction
        address currOwner = IERC721(auction.tokenContract).ownerOf(auction.tokenId);
        require(currOwner != auction.tokenOwner || auction.tokenOwner == msg.sender, "cancelAuction only callable by auction creator");

        emit AuctionCanceled(_auctionId, auction.tokenId, auction.tokenContract, auction.tokenOwner);

        delete _self.auctions[_auctionId];
    }

    function _exists(ReserveAuctionStorage storage _self, uint256 _auctionId) private view returns (bool) {
        return _self.auctions[_auctionId].tokenOwner != address(0);
    }

    function _handleOutgoingTransfer(
        ReserveAuctionStorage storage _self,
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        if (_amount == 0 || _dest == address(0)) {
            return;
        }
        if (_currency == address(0)) {
            _handleOutgoingETHTransfer(_self, _dest, _amount);
        } else {
            _handleOutgoingERC20Transfer(_dest, _amount, _currency);
        }
    }

    // Sending ETH is not guaranteed complete, and the method used here will send WETH if the ETH transfer fails.
    // For example, a contract can block ETH transfer, or might use
    // an excessive amount of gas, thereby griefing a new bidder.
    // We should limit the gas used in transfers, and handle failure cases.
    function _handleOutgoingETHTransfer(
        ReserveAuctionStorage storage _self,
        address _dest,
        uint256 _amount
    ) private {
        require(address(this).balance >= _amount, "ReserveAuctionV1::_handleOutgoingETHTransfer insolvent");
        // Here increase the gas limit a reasonable amount above the default, and try
        // to send ETH to the recipient.
        (bool success, ) = _dest.call{value: _amount, gas: 30000}(new bytes(0));

        // If the ETH transfer fails (sigh), wrap the ETH and try send it as WETH.
        if (!success) {
            IWETH(_self.wethAddress).deposit{value: _amount}();
            IERC20(_self.wethAddress).safeTransfer(_dest, _amount);
        }
    }

    function _handleOutgoingERC20Transfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        IERC20(_currency).safeTransfer(_dest, _amount);
    }

    function _handleIncomingTransfer(
        ReserveAuctionStorage storage _self,
        uint256 _amount,
        address _currency
    ) private {
        if (_currency == address(0)) {
            require(msg.value >= _amount, "_handleIncomingTransfer msg value less than expected amount");
        } else {
            // We must check the balance that was actually transferred to the auction,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            ERC20TransferHelper(_self.erc20TransferHelper).safeTransferFrom(_currency, msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            require(beforeBalance.add(_amount) == afterBalance, "_handleIncomingERC20Transfer token transfer call did not transfer expected amount");
        }
    }

    function _handleZoraAuctionPayout(ReserveAuctionStorage storage _self, uint256 _auctionId) private returns (uint256) {
        IZoraV1Market.BidShares memory bidShares = IZoraV1Market(_self.zoraV1ProtocolMarket).bidSharesForToken(_self.auctions[_auctionId].tokenId);

        Auction memory auction = _self.auctions[_auctionId];

        uint256 creatorProfit = IZoraV1Market(_self.zoraV1ProtocolMarket).splitShare(bidShares.creator, auction.amount);
        uint256 prevOwnerProfit = IZoraV1Market(_self.zoraV1ProtocolMarket).splitShare(bidShares.prevOwner, auction.amount);

        // Pay out creator
        _handleOutgoingTransfer(_self, IZoraV1Media(_self.zoraV1ProtocolMedia).tokenCreators(auction.tokenId), creatorProfit, auction.auctionCurrency);
        // Pay out prev owner
        _handleOutgoingTransfer(_self, IZoraV1Media(_self.zoraV1ProtocolMedia).previousTokenOwners(auction.tokenId), prevOwnerProfit, auction.auctionCurrency);

        return auction.amount.sub(creatorProfit).sub(prevOwnerProfit);
    }

    function _handleEIP2981AuctionPayout(ReserveAuctionStorage storage _self, uint256 _auctionId) private returns (uint256) {
        Auction memory auction = _self.auctions[_auctionId];

        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(auction.tokenContract).royaltyInfo(auction.tokenId, auction.amount);

        // Pay out royalty receiver
        _handleOutgoingTransfer(_self, royaltyReceiver, royaltyAmount, auction.auctionCurrency);

        return auction.amount.sub(royaltyAmount);
    }

    function _handleRoyaltyRegistryPayout(ReserveAuctionStorage storage _self, uint256 _auctionId) private returns (uint256) {
        Auction memory auction = _self.auctions[_auctionId];
        (address royaltyReceiver, uint8 royaltyPercentage) = CollectionRoyaltyRegistryV1(_self.royaltyRegistry).collectionRoyalty(auction.tokenContract);

        uint256 remainingProfit = auction.amount;

        uint256 royaltyAmount = remainingProfit.mul(royaltyPercentage).div(100);
        _handleOutgoingTransfer(_self, royaltyReceiver, royaltyAmount, auction.auctionCurrency);

        remainingProfit -= royaltyAmount;

        return remainingProfit;
    }
}
