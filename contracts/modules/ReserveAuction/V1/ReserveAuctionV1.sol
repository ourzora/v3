// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IModule} from "../../../interfaces/IModule.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface IMarket {
    struct Decimal {
        uint256 value;
    }

    struct BidShares {
        // % of sale value that goes to the _previous_ owner of the nft
        Decimal prevOwner;
        // % of sale value that goes to the original creator of the nft
        Decimal creator;
        // % of sale value that goes to the seller (current owner) of the nft
        Decimal owner;
    }

    function isValidBid(uint256 tokenId, uint256 bidAmount)
        external
        view
        returns (bool);

    function bidSharesForToken(uint256 tokenId)
        external
        view
        returns (BidShares memory);

    function splitShare(Decimal memory share, uint256 amount)
        external
        pure
        returns (uint256);
}

interface IMedia is IERC721 {
    function marketContract() external view returns (address);

    function tokenCreators(uint256 tokenId) external view returns (address);

    function previousTokenOwner(uint256 tokenId)
        external
        view
        returns (address);
}

interface IERC2981 {
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

contract ReserveAuctionV1 is IModule, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant VERSION = 1;
    bytes32 internal constant TEST_MODULE_STORAGE_POSITION =
        keccak256("ReserveAuction.V1");
    bytes4 constant interfaceId = 0x80ac58cd; // ERC-721 interface ID

    event AuctionCreated(
        uint256 indexed auctionId,
        uint256 indexed tokenId,
        address indexed tokenContract,
        uint256 duration,
        uint256 timeBuffer,
        uint8 minimumIncrementPercentage,
        uint256 reservePrice,
        address tokenOwner,
        address curator,
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
        address tokenOwner,
        address curator,
        address winner,
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
        // The minimum amount of time left in the auction after a new bid is created
        uint256 timeBuffer;
        // The minimum percentage difference between the last bid and the current bid
        uint8 minimumIncrementPercentage;
        // The time of the first bid
        uint256 firstBidTime;
        // The minimum price of the first bid
        uint256 reservePrice;
        // The sale percentage to send to the curator
        uint8 curatorFeePercentage;
        // The address of the token owner who is placing the token in escrow
        address tokenOwner;
        // The address of the current highest bidder
        address payable bidder;
        // The address of the auction's curator.
        // The curator can reject or approve an auction
        address payable curator;
        // The address to send the auction's winning bid funds to
        address fundsRecipient;
        // The address of the ERC-20 currency to run the auction with.
        // If set to 0x0, the auction will be run in ETH
        address auctionCurrency;
    }

    struct AuctionCreationParams {
        uint256 tokenId;
        address tokenContract;
        uint256 duration;
        uint256 timeBuffer;
        uint8 minimumIncrementPercentage;
        uint256 reservePrice;
        address payable curator;
        address fundsRecipient;
        uint8 curatorFeePercentage;
        address auctionCurrency;
    }

    struct ReserveAuctionStorage {
        bool initialized;
        address zoraV1ProtocolMedia;
        address zoraV1ProtocolMarket;
        address wethAddress;
        Counters.Counter auctionIdTracker;
        mapping(uint256 => Auction) auctions;
    }

    modifier auctionExists(uint256 _auctionId) {
        require(_exists(_auctionId), "Auction doesn't exist");
        _;
    }

    function version() external pure override returns (uint256) {
        return VERSION;
    }

    function initialize(address _zoraV1ProtocolMedia, address _wethAddress)
        external
    {
        // This call should technically be internal, but we must make it external to add it to the table of functions
        // so it can be called via delegatecall.
        // Hence, we ensure below that the method can only be called by itself.
        require(
            msg.sender == address(this),
            "ReserveAuctionV1::initialize can not be called by external address"
        );
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        s.zoraV1ProtocolMedia = _zoraV1ProtocolMedia;
        s.zoraV1ProtocolMarket = IMedia(_zoraV1ProtocolMedia).marketContract();
        s.wethAddress = _wethAddress;
        s.initialized = true;
    }

    function createAuction(AuctionCreationParams memory _params)
        public
        nonReentrant
        returns (uint256)
    {
        require(
            IERC165(_params.tokenContract).supportsInterface(interfaceId),
            "ReserveAuctionV1::createAuction tokenContract does not support ERC721 interface"
        );
        require(
            _params.curatorFeePercentage < 100,
            "ReserveAuctionV1::createAuction curatorFeePercentage must be less than 100"
        );
        address tokenOwner = IERC721(_params.tokenContract).ownerOf(
            _params.tokenId
        );
        require(
            msg.sender ==
                IERC721(_params.tokenContract).getApproved(_params.tokenId) ||
                msg.sender == tokenOwner,
            "ReserveAuctionV1::createAuction caller must be approved or owner for token id"
        );
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        uint256 auctionId = s.auctionIdTracker.current();

        s.auctions[auctionId] = Auction({
            tokenId: _params.tokenId,
            tokenContract: _params.tokenContract,
            approved: false,
            amount: 0,
            duration: _params.duration,
            timeBuffer: _params.timeBuffer,
            minimumIncrementPercentage: _params.minimumIncrementPercentage,
            firstBidTime: 0,
            reservePrice: _params.reservePrice,
            curatorFeePercentage: _params.curatorFeePercentage,
            tokenOwner: tokenOwner,
            bidder: payable(address(0)),
            curator: _params.curator,
            fundsRecipient: _params.fundsRecipient,
            auctionCurrency: _params.auctionCurrency
        });

        IERC721(_params.tokenContract).transferFrom(
            tokenOwner,
            address(this),
            _params.tokenId
        );

        s.auctionIdTracker.increment();

        emit AuctionCreated(
            auctionId,
            _params.tokenId,
            _params.tokenContract,
            _params.duration,
            _params.timeBuffer,
            _params.minimumIncrementPercentage,
            _params.reservePrice,
            tokenOwner,
            _params.curator,
            _params.curatorFeePercentage,
            _params.auctionCurrency
        );

        return auctionId;
    }

    function setAuctionApproval(
        uint256, /*_version*/
        uint256 _auctionId,
        bool _approved
    ) external auctionExists(_auctionId) {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        require(
            msg.sender == s.auctions[_auctionId].curator,
            "ReserveAuctionV1::setAuctionApproval must be auction curator"
        );
        require(
            s.auctions[_auctionId].firstBidTime == 0,
            "ReserveAuctionV1::setAuctionApproval auction has already started"
        );
        _approveAuction(_auctionId, _approved);
    }

    function setAuctionReservePrice(
        uint256, /*_version*/
        uint256 _auctionId,
        uint256 _reservePrice
    ) external auctionExists(_auctionId) {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        require(
            msg.sender == s.auctions[_auctionId].curator ||
                msg.sender == s.auctions[_auctionId].tokenOwner,
            "ReserveAuctionV1::setAuctionReservePrice must be auction curator or token owner"
        );
        require(
            s.auctions[_auctionId].firstBidTime == 0,
            "ReserveAuctionV1::setAuctionReservePrice auction has already started"
        );

        s.auctions[_auctionId].reservePrice = _reservePrice;
        emit AuctionReservePriceUpdated(
            _auctionId,
            s.auctions[_auctionId].tokenId,
            s.auctions[_auctionId].tokenContract,
            _reservePrice
        );
    }

    function createBid(
        uint256, /*_version*/
        uint256 _auctionId,
        uint256 _amount
    ) external payable auctionExists(_auctionId) nonReentrant {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        address payable lastBidder = s.auctions[_auctionId].bidder;
        require(
            s.auctions[_auctionId].approved,
            "ReserveAuctionV1::createBid auction must be approved"
        );
        require(
            s.auctions[_auctionId].firstBidTime == 0 ||
                block.timestamp <
                s.auctions[_auctionId].firstBidTime.add(
                    s.auctions[_auctionId].duration
                ),
            "ReserveAuctionV1::createBid auction expired"
        );
        require(
            _amount >= s.auctions[_auctionId].reservePrice,
            "ReserveAuctionV1::createBid must send at least reserve price"
        );
        require(
            _amount >=
                s.auctions[_auctionId].amount.add(
                    s
                    .auctions[_auctionId]
                    .amount
                    .mul(s.auctions[_auctionId].minimumIncrementPercentage)
                    .div(100)
                ),
            "ReserveAuctionV1::createBid must send more than last bid by minimumIncrementPercentage amount"
        );

        // For Zora V1 Protocol, ensure that the bid is valid for the current bid share configuration
        if (s.auctions[_auctionId].tokenContract == s.zoraV1ProtocolMedia) {
            require(
                IMarket(s.zoraV1ProtocolMarket).isValidBid(
                    s.auctions[_auctionId].tokenId,
                    _amount
                ),
                "ReserveAuctionV1::createBid bid invalid for share splitting"
            );
        }

        // If this is the first valid bid, we should set the starting time now.
        // If it's not, then we should refund the last bidder
        if (s.auctions[_auctionId].firstBidTime == 0) {
            s.auctions[_auctionId].firstBidTime = block.timestamp;
        } else if (lastBidder != address(0)) {
            _handleOutgoingTransfer(
                lastBidder,
                s.auctions[_auctionId].amount,
                s.auctions[_auctionId].auctionCurrency
            );
        }

        _handleIncomingTransfer(
            _amount,
            s.auctions[_auctionId].auctionCurrency
        );

        s.auctions[_auctionId].amount = _amount;
        s.auctions[_auctionId].bidder = payable(address(msg.sender));

        bool extended = false;
        // at this point we know that the timestamp is less than start + duration (since the auction would be over, otherwise)
        // we want to know by how much the timestamp is less than start + duration
        // if the difference is less than the timeBuffer, increase the duration by the timeBuffer
        if (
            s
            .auctions[_auctionId]
            .firstBidTime
            .add(s.auctions[_auctionId].duration)
            .sub(block.timestamp) < s.auctions[_auctionId].timeBuffer
        ) {
            // Playing code golf for gas optimization:
            // uint256 expectedEnd = auctions[auctionId].firstBidTime.add(auctions[auctionId].duration);
            // uint256 timeRemaining = expectedEnd.sub(block.timestamp);
            // uint256 timeToAdd = timeBuffer.sub(timeRemaining);
            // uint256 newDuration = auctions[auctionId].duration.add(timeToAdd);
            uint256 oldDuration = s.auctions[_auctionId].duration;
            s.auctions[_auctionId].duration = oldDuration.add(
                s.auctions[_auctionId].timeBuffer.sub(
                    s.auctions[_auctionId].firstBidTime.add(oldDuration).sub(
                        block.timestamp
                    )
                )
            );
            extended = true;
        }

        emit AuctionBid(
            _auctionId,
            s.auctions[_auctionId].tokenId,
            s.auctions[_auctionId].tokenContract,
            msg.sender,
            _amount,
            lastBidder == address(0), // firstBid boolean
            extended
        );

        if (extended) {
            emit AuctionDurationExtended(
                _auctionId,
                s.auctions[_auctionId].tokenId,
                s.auctions[_auctionId].tokenContract,
                s.auctions[_auctionId].duration
            );
        }
    }

    function endAuction(
        uint256, /*_version*/
        uint256 _auctionId
    ) external auctionExists(_auctionId) nonReentrant {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        require(
            s.auctions[_auctionId].firstBidTime != 0,
            "ReserveAuctionV1::endAuction auction hasn't begun"
        );
        require(
            block.timestamp >=
                s.auctions[_auctionId].firstBidTime.add(
                    s.auctions[_auctionId].duration
                ),
            "ReserveAuctionV1::endAuction auction hasn't completed"
        );

        // TODO dis bit right here
        if (s.auctions[_auctionId].tokenContract == s.zoraV1ProtocolMedia) {
            _handleZoraAuctionPayout(_auctionId);
        } else if (
            IERC165(s.auctions[_auctionId].tokenContract).supportsInterface(
                // INTERFACE_ID_ERC2981
                0x2a55205a
            )
        ) {
            _handleEIP2981AuctionPayout(_auctionId);
        } else {
            _handleVanillaAuctionPayout(_auctionId);
        }

        // remove the royalties from the profit
        // split the shares
    }

    function _reserveAuctionStorage()
        internal
        pure
        returns (ReserveAuctionStorage storage s)
    {
        bytes32 position = TEST_MODULE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function _exists(uint256 _auctionId) internal view returns (bool) {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        return s.auctions[_auctionId].tokenOwner != address(0);
    }

    function _approveAuction(uint256 _auctionId, bool approved) internal {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        s.auctions[_auctionId].approved = approved;
        emit AuctionApprovalUpdated(
            _auctionId,
            s.auctions[_auctionId].tokenId,
            s.auctions[_auctionId].tokenContract,
            approved
        );
    }

    function _handleOutgoingTransfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) internal {
        if (_currency == address(0)) {
            _handleOutgoingETHTransfer(_dest, _amount);
        } else {
            _handleOutgoingERC20Transfer(_dest, _amount, _currency);
        }
    }

    function _handleIncomingTransfer(uint256 _amount, address _currency)
        internal
    {
        if (_currency == address(0)) {
            _handleIncomingETHTransfer(_amount);
        } else {
            _handleIncomingERC20Transfer(_amount, _currency);
        }
    }

    function _handleOutgoingETHTransfer(address _dest, uint256 _amount)
        internal
    {
        require(
            address(this).balance >= _amount,
            "ReserveAuctionV1::_handleOutgoingETHTransfer insolvent"
        );
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        (bool success, ) = _dest.call{value: _amount}(new bytes(0));

        // If the ETH transfer fails (sigh), wrap the ETH and try send it as WETH.
        if (!success) {
            IWETH(s.wethAddress).deposit{value: _amount}();
            IERC20(s.wethAddress).safeTransfer(_dest, _amount);
        }
    }

    function _handleOutgoingERC20Transfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) internal {
        IERC20(_currency).safeTransfer(_dest, _amount);
    }

    function _handleIncomingETHTransfer(uint256 _amount) internal {
        require(
            msg.value >= _amount,
            "ReserveAuctionV1::_handleIncomingETHTransfer msg value less than expected amount"
        );
    }

    function _handleIncomingERC20Transfer(uint256 _amount, address _currency)
        internal
    {
        // We must check the balance that was actually transferred to the auction,
        // as some tokens impose a transfer fee and would not actually transfer the
        // full amount to the market, resulting in potentally locked funds
        IERC20 token = IERC20(_currency);
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterBalance = token.balanceOf(address(this));
        require(
            beforeBalance.add(_amount) == afterBalance,
            "ReserveAuctionV1::_handleIncomingERC20Transfer token transfer call did not transfer expected amount"
        );
    }

    function _handleZoraAuctionPayout(uint256 _auctionId) internal {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        IMarket.BidShares memory bidShares = IMarket(s.zoraV1ProtocolMarket)
        .bidSharesForToken(s.auctions[_auctionId].tokenId);

        Auction memory auction = s.auctions[_auctionId];

        uint256 creatorProfit = IMarket(s.zoraV1ProtocolMarket).splitShare(
            bidShares.creator,
            auction.amount
        );
        uint256 prevOwnerProfit = IMarket(s.zoraV1ProtocolMarket).splitShare(
            bidShares.prevOwner,
            auction.amount
        );

        // Pay out creator
        _handleOutgoingTransfer(
            IMedia(s.zoraV1ProtocolMedia).tokenCreators(auction.tokenId),
            creatorProfit,
            auction.auctionCurrency
        );

        // Pay out prev owner
        _handleOutgoingTransfer(
            IMedia(s.zoraV1ProtocolMedia).previousTokenOwner(auction.tokenId),
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
                auction.curator,
                curatorProfit,
                auction.auctionCurrency
            );
        }
        _handleOutgoingTransfer(
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
    }

    function _handleEIP2981AuctionPayout(uint256 _auctionId) internal {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        Auction memory auction = s.auctions[_auctionId];

        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(
            auction.tokenContract
        ).royaltyInfo(auction.tokenId, auction.amount);

        uint256 profit = auction.amount;
        // Pay out royalty receiver
        if (royaltyAmount != 0 && royaltyReceiver != address(0)) {
            profit = profit.sub(royaltyAmount);
            _handleOutgoingTransfer(
                royaltyReceiver,
                royaltyAmount,
                auction.auctionCurrency
            );
        }

        // Pay out the funds recipient
        _handleOutgoingTransfer(
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
    }

    function _handleVanillaAuctionPayout(uint256 _auctionId) internal {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        Auction memory auction = s.auctions[_auctionId];

        // Pay out the funds recipient
        _handleOutgoingTransfer(
            auction.fundsRecipient,
            auction.amount,
            auction.auctionCurrency
        );

        // Transfer NFT to winner
        IERC721(auction.tokenContract).safeTransferFrom(
            address(this),
            auction.bidder,
            auction.tokenId
        );
    }
}
