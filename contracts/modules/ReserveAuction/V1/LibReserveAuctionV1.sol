// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IModule} from "../../../interfaces/IModule.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";

library LibReserveAuctionV1 {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct ReserveAuctionStorage {
        bool initialized;
        address zoraV1ProtocolMedia;
        address zoraV1ProtocolMarket;
        uint256 timeBuffer;
        uint8 minBidIncrementPercentage;
        address wethAddress;
        Counters.Counter auctionIdTracker;
        mapping(uint256 => Auction) auctions;
    }

    bytes4 constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    struct Auction {
        // ID for the ERC721 token
        uint256 tokenId;
        // Address for the ERC721 contract
        address tokenContract;
        // Whether or not the auction curator has approved the auction to start
        bool approved;
        // The current highest bid amount
        uint256 amount;
        // The length of time to run the auction for, after the first bid was made
        uint256 duration;
        // The time of the first bid
        uint256 firstBidTime;
        // The minimum price of the first bid
        uint256 reservePrice;
        // The sale percentage to send to the curator
        uint8 curatorFeePercentage;
        // The address that should receive the funds once the NFT is sold.
        address tokenOwner;
        // The address of the current highest bid
        address payable bidder;
        // The address of the auction's curator.
        // The curator can reject or approve an auction
        address payable curator;
        // The address of the recipient of the auction's highest bid
        address payable fundsRecipient;
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
        address curator,
        address fundsRecipient,
        uint8 curatorFeePercentage,
        address auctionCurrency
    );

    event AuctionApprovalUpdated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        bool approved
    );

    event AuctionReservePriceUpdated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 reservePrice
    );

    event AuctionBid(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address sender,
        uint256 value,
        bool firstBid,
        bool extended
    );

    event AuctionDurationExtended(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 duration
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address curator,
        address winner,
        address fundsRecipient,
        uint256 amount,
        uint256 curatorFee,
        address auctionCurrency
    );

    event AuctionCanceled(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        address tokenOwner
    );

    /**
     * @notice Require that the specified auction exists
     */
    modifier auctionExists(
        ReserveAuctionStorage storage _self,
        uint256 auctionId
    ) {
        require(
            _exists(_self, auctionId),
            "auctionExists auction doesn't exist"
        );
        _;
    }

    function init(
        ReserveAuctionStorage storage _self,
        address _zoraV1ProtocolMedia,
        address _wethAddress
    ) internal {
        require(_self.initialized != true, "init already initialized");
        _self.zoraV1ProtocolMedia = _zoraV1ProtocolMedia;
        _self.zoraV1ProtocolMarket = IZoraV1Media(_zoraV1ProtocolMedia)
        .marketContract();
        _self.wethAddress = _wethAddress;
        _self.initialized = true;
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the auctions mapping and emit an AuctionCreated event.
     * If there is no curator, or if the curator is the auction creator, automatically approve the auction.
     */
    function createAuction(
        ReserveAuctionStorage storage _self,
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _curator,
        address payable _fundsRecipient,
        uint8 _curatorFeePercentage,
        address _auctionCurrency
    ) internal returns (uint256) {
        require(
            IERC165(_tokenContract).supportsInterface(ERC721_INTERFACE_ID),
            "createAuction tokenContract does not support ERC721 interface"
        );
        require(
            _curatorFeePercentage < 100,
            "createAuction curatorFeePercentage must be less than 100"
        );
        require(
            _fundsRecipient != address(0),
            "createAuction fundsRecipient cannot be 0 address"
        );
        require(
            IERC721(_tokenContract).getApproved(_tokenId) == msg.sender ||
                IERC721(_tokenContract).ownerOf(_tokenId) == msg.sender,
            "createAuction caller must be approved or owner for token id"
        );
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        uint256 auctionId = _self.auctionIdTracker.current();

        _self.auctions[auctionId] = Auction({
            tokenId: _tokenId,
            tokenContract: _tokenContract,
            approved: false,
            amount: 0,
            duration: _duration,
            firstBidTime: 0,
            reservePrice: _reservePrice,
            curatorFeePercentage: _curatorFeePercentage,
            tokenOwner: tokenOwner,
            bidder: payable(address(0)),
            curator: _curator,
            fundsRecipient: _fundsRecipient,
            auctionCurrency: _auctionCurrency
        });

        IERC721(_tokenContract).transferFrom(
            tokenOwner,
            address(this),
            _tokenId
        );

        _self.auctionIdTracker.increment();

        emit AuctionCreated(
            auctionId,
            _tokenId,
            _tokenContract,
            _duration,
            _reservePrice,
            tokenOwner,
            _curator,
            _fundsRecipient,
            _curatorFeePercentage,
            _auctionCurrency
        );

        if (
            _self.auctions[auctionId].curator == address(0) ||
            _curator == tokenOwner
        ) {
            _approveAuction(_self, auctionId, true);
        }

        return auctionId;
    }

    /**
     * @notice Approve an auction, opening up the auction for bids.
     * @dev Only callable by the curator. Cannot be called if the auction has already started.
     */
    function setAuctionApproval(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        bool _approved
    ) internal auctionExists(_self, _auctionId) {
        require(
            msg.sender == _self.auctions[_auctionId].curator,
            "setAuctionApproval must be auction curator"
        );
        require(
            _self.auctions[_auctionId].firstBidTime == 0,
            "setAuctionApproval auction has already started"
        );
        _approveAuction(_self, _auctionId, _approved);
    }

    /**
     * @notice Create a bid on a token, with a given amount.
     * @dev If provided a valid bid, transfers the provided amount to this contract.
     * If the auction is run in native ETH, the ETH is wrapped so it can be identically to other
     * auction currencies in this contract.
     */
    function setAuctionReservePrice(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        uint256 _reservePrice
    ) internal auctionExists(_self, _auctionId) {
        require(
            msg.sender == _self.auctions[_auctionId].curator ||
                msg.sender == _self.auctions[_auctionId].tokenOwner,
            "setAuctionReservePrice must be auction curator or token owner"
        );
        require(
            _self.auctions[_auctionId].firstBidTime == 0,
            "setAuctionReservePrice auction has already started"
        );

        _self.auctions[_auctionId].reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(
            _auctionId,
            _self.auctions[_auctionId].tokenId,
            _self.auctions[_auctionId].tokenContract,
            _reservePrice
        );
    }

    /**
     * @notice Create a bid on a token, with a given amount.
     * @dev If provided a valid bid, transfers the provided amount to this contract.
     */
    function createBid(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        uint256 _amount
    ) internal auctionExists(_self, _auctionId) {
        address payable lastBidder = _self.auctions[_auctionId].bidder;
        require(
            _self.auctions[_auctionId].approved,
            "createBid auction must be approved by curator"
        );
        require(
            _self.auctions[_auctionId].firstBidTime == 0 ||
                block.timestamp <
                _self.auctions[_auctionId].firstBidTime.add(
                    _self.auctions[_auctionId].duration
                ),
            "createBid auction expired"
        );
        require(
            _amount >=
                _self.auctions[_auctionId].amount.add(
                    _self
                    .auctions[_auctionId]
                    .amount
                    .mul(_self.minBidIncrementPercentage)
                    .div(100)
                ),
            "createBid must send more than the last bid by minBidIncrementPercentage amount"
        );

        // For Zora V1 Protocol, ensure that the bid is valid for the current bidShare configuration
        if (
            _self.auctions[_auctionId].tokenContract ==
            _self.zoraV1ProtocolMedia
        ) {
            require(
                IZoraV1Market(_self.zoraV1ProtocolMarket).isValidBid(
                    _self.auctions[_auctionId].tokenId,
                    _amount
                ),
                "createBid bid invalid for share splitting"
            );
        }

        // If this is the first valid bid, we should set the starting time now.
        // If it's not, then we should refund the last bidder
        if (_self.auctions[_auctionId].firstBidTime == 0) {
            _self.auctions[_auctionId].firstBidTime = block.timestamp;
        } else if (lastBidder != address(0)) {
            _handleOutgoingTransfer(
                _self,
                lastBidder,
                _self.auctions[_auctionId].amount,
                _self.auctions[_auctionId].auctionCurrency
            );
        }

        _handleIncomingTransfer(
            _amount,
            _self.auctions[_auctionId].auctionCurrency
        );

        _self.auctions[_auctionId].amount = _amount;
        _self.auctions[_auctionId].bidder = payable(msg.sender);

        bool extended = false;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if (
            _self
            .auctions[_auctionId]
            .firstBidTime
            .add(_self.auctions[_auctionId].duration)
            .sub(block.timestamp) < _self.timeBuffer
        ) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionId].firstBidTime.add(auctions[auctionId].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionId].duration.add(timeToAdd);
            uint256 oldDuration = _self.auctions[_auctionId].duration;
            _self.auctions[_auctionId].duration = oldDuration.add(
                _self.timeBuffer.sub(
                    _self
                    .auctions[_auctionId]
                    .firstBidTime
                    .add(oldDuration)
                    .sub(block.timestamp)
                )
            );
            extended = true;
        }

        emit AuctionBid(
            _auctionId,
            _self.auctions[_auctionId].tokenId,
            _self.auctions[_auctionId].tokenContract,
            msg.sender,
            _amount,
            lastBidder == address(0), // firstBid boolean
            extended
        );

        if (extended) {
            emit AuctionDurationExtended(
                _auctionId,
                _self.auctions[_auctionId].tokenId,
                _self.auctions[_auctionId].tokenContract,
                _self.auctions[_auctionId].duration
            );
        }
    }

    /**
     * @notice End an auction, finalizing the bid on Zora if applicable and paying out the respective parties.
     * @dev If for some reason the auction cannot be finalized (invalid token recipient, for example),
     * The auction is reset and the NFT is transferred back to the auction creator.
     */
    function endAuction(ReserveAuctionStorage storage _self, uint256 _auctionId)
        internal
        auctionExists(_self, _auctionId)
    {
        require(
            _self.auctions[_auctionId].firstBidTime != 0,
            "ReserveAuctionV1::endAuction auction hasn't begun"
        );
        require(
            block.timestamp >=
                _self.auctions[_auctionId].firstBidTime.add(
                    _self.auctions[_auctionId].duration
                ),
            "ReserveAuctionV1::endAuction auction hasn't completed"
        );

        uint256 fundsRecipientProfit;
        uint256 curatorFee;
        if (
            _self.auctions[_auctionId].tokenContract ==
            _self.zoraV1ProtocolMedia
        ) {
            (fundsRecipientProfit, curatorFee) = _handleZoraAuctionPayout(
                _self,
                _auctionId
            );
        } else if (
            IERC165(_self.auctions[_auctionId].tokenContract).supportsInterface(
                ERC2981_INTERFACE_ID
            )
        ) {
            (fundsRecipientProfit, curatorFee) = _handleEIP2981AuctionPayout(
                _self,
                _auctionId
            );
        } else {
            (fundsRecipientProfit, curatorFee) = _handleVanillaAuctionPayout(
                _self,
                _auctionId
            );
        }

        emit AuctionEnded(
            _auctionId,
            _self.auctions[_auctionId].tokenId,
            _self.auctions[_auctionId].tokenContract,
            _self.auctions[_auctionId].curator,
            _self.auctions[_auctionId].bidder,
            _self.auctions[_auctionId].fundsRecipient,
            fundsRecipientProfit,
            curatorFee,
            _self.auctions[_auctionId].auctionCurrency
        );

        delete _self.auctions[_auctionId];
    }

    /**
     * @notice Cancel an auction.
     * @dev Transfers the NFT back to the auction creator and emits an AuctionCanceled event
     */
    function cancelAuction(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId
    ) internal auctionExists(_self, _auctionId) {
        require(
            _self.auctions[_auctionId].tokenOwner == msg.sender ||
                _self.auctions[_auctionId].curator == msg.sender,
            "cancelAuction only callable by curator or auction creator"
        );
        require(
            _self.auctions[_auctionId].firstBidTime == 0,
            "cancelAuction auction already started"
        );

        IERC721(_self.auctions[_auctionId].tokenContract).safeTransferFrom(
            address(this),
            _self.auctions[_auctionId].tokenOwner,
            _self.auctions[_auctionId].tokenId
        );
        emit AuctionCanceled(
            _auctionId,
            _self.auctions[_auctionId].tokenId,
            _self.auctions[_auctionId].tokenContract,
            _self.auctions[_auctionId].tokenOwner
        );

        delete _self.auctions[_auctionId];
    }

    function _approveAuction(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId,
        bool _approved
    ) private {
        _self.auctions[_auctionId].approved = _approved;
        emit AuctionApprovalUpdated(
            _auctionId,
            _self.auctions[_auctionId].tokenId,
            _self.auctions[_auctionId].tokenContract,
            _approved
        );
    }

    function _exists(ReserveAuctionStorage storage _self, uint256 _auctionId)
        private
        view
        returns (bool)
    {
        return _self.auctions[_auctionId].tokenOwner != address(0);
    }

    function _handleOutgoingTransfer(
        ReserveAuctionStorage storage _self,
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
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
        require(
            address(this).balance >= _amount,
            "ReserveAuctionV1::_handleOutgoingETHTransfer insolvent"
        );
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

    function _handleIncomingTransfer(uint256 _amount, address _currency)
        private
    {
        if (_currency == address(0)) {
            require(
                msg.value >= _amount,
                "_handleIncomingTransfer msg value less than expected amount"
            );
        } else {
            // We must check the balance that was actually transferred to the auction,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            require(
                beforeBalance.add(_amount) == afterBalance,
                "_handleIncomingERC20Transfer token transfer call did not transfer expected amount"
            );
        }
    }

    function _handleZoraAuctionPayout(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId
    ) private returns (uint256, uint256) {
        IZoraV1Market.BidShares memory bidShares = IZoraV1Market(
            _self.zoraV1ProtocolMarket
        ).bidSharesForToken(_self.auctions[_auctionId].tokenId);

        Auction memory auction = _self.auctions[_auctionId];

        uint256 creatorProfit = IZoraV1Market(_self.zoraV1ProtocolMarket)
        .splitShare(bidShares.creator, auction.amount);
        uint256 prevOwnerProfit = IZoraV1Market(_self.zoraV1ProtocolMarket)
        .splitShare(bidShares.prevOwner, auction.amount);

        // Pay out creator
        _handleOutgoingTransfer(
            _self,
            IZoraV1Media(_self.zoraV1ProtocolMedia).tokenCreators(
                auction.tokenId
            ),
            creatorProfit,
            auction.auctionCurrency
        );

        // Pay out prev owner
        _handleOutgoingTransfer(
            _self,
            IZoraV1Media(_self.zoraV1ProtocolMedia).previousTokenOwner(
                auction.tokenId
            ),
            prevOwnerProfit,
            auction.auctionCurrency
        );

        // Pay out curator and funds recipient
        uint256 curatorProfit;
        uint256 remainingProfit = auction.amount.sub(creatorProfit).sub(
            prevOwnerProfit
        );
        if (auction.curator != address(0)) {
            curatorProfit = remainingProfit
            .mul(auction.curatorFeePercentage)
            .div(100);
            remainingProfit = remainingProfit.sub(curatorProfit);
            _handleOutgoingTransfer(
                _self,
                auction.curator,
                curatorProfit,
                auction.auctionCurrency
            );
        }
        _handleOutgoingTransfer(
            _self,
            auction.fundsRecipient,
            remainingProfit,
            auction.auctionCurrency
        );

        // Transfer NFT to winner
        IERC721(auction.tokenContract).safeTransferFrom(
            address(this),
            auction.bidder,
            auction.tokenId
        );

        return (remainingProfit, curatorProfit);
    }

    function _handleEIP2981AuctionPayout(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId
    ) private returns (uint256, uint256) {
        Auction memory auction = _self.auctions[_auctionId];

        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(
            auction.tokenContract
        ).royaltyInfo(auction.tokenId, auction.amount);

        uint256 profit = auction.amount;
        // Pay out royalty receiver
        if (royaltyAmount != 0 && royaltyReceiver != address(0)) {
            profit = profit.sub(royaltyAmount);
            _handleOutgoingTransfer(
                _self,
                royaltyReceiver,
                royaltyAmount,
                auction.auctionCurrency
            );
        }

        // Pay out curator and funds recipient
        uint256 curatorProfit;
        if (auction.curator != address(0)) {
            curatorProfit = profit.mul(auction.curatorFeePercentage).div(100);
            profit = profit.sub(curatorProfit);
            _handleOutgoingTransfer(
                _self,
                auction.curator,
                curatorProfit,
                auction.auctionCurrency
            );
        }

        // Pay out the funds recipient
        _handleOutgoingTransfer(
            _self,
            auction.fundsRecipient,
            profit,
            auction.auctionCurrency
        );

        // Transfer NFT to winner
        IERC721(auction.tokenContract).safeTransferFrom(
            address(this),
            auction.bidder,
            auction.tokenId
        );

        return (profit, curatorProfit);
    }

    function _handleVanillaAuctionPayout(
        ReserveAuctionStorage storage _self,
        uint256 _auctionId
    ) private returns (uint256, uint256) {
        Auction memory auction = _self.auctions[_auctionId];
        uint256 profit = auction.amount;

        // Pay out curator and funds recipient
        uint256 curatorProfit;
        if (auction.curator != address(0)) {
            curatorProfit = profit.mul(auction.curatorFeePercentage).div(100);
            profit = profit.sub(curatorProfit);
            _handleOutgoingTransfer(
                _self,
                auction.curator,
                curatorProfit,
                auction.auctionCurrency
            );
        }

        // Pay out the funds recipient
        _handleOutgoingTransfer(
            _self,
            auction.fundsRecipient,
            profit,
            auction.auctionCurrency
        );

        // Transfer NFT to winner
        IERC721(auction.tokenContract).safeTransferFrom(
            address(this),
            auction.bidder,
            auction.tokenId
        );

        return (profit, curatorProfit);
    }
}
