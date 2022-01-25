// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionV1} from "../../../../modules/ReserveAuction/V1/ReserveAuctionV1.sol";
import {Zorb} from "../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../utils/modules/RoyaltyEngine.sol";

import {TestERC721} from "../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../utils/tokens/WETH.sol";
import {VM} from "../../../utils/VM.sol";

/// @title ReserveAuctionV1Test
/// @notice Unit Tests for Reserve Auction v1.0
contract ReserveAuctionV1Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    ReserveAuctionV1 internal auctions;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal finder;
    Zorb internal royaltyRecipient;
    Zorb internal bidder;
    Zorb internal otherBidder;

    function setUp() public {
        // Cheatcodes
        vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
        erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create users
        seller = new Zorb(address(ZMM));
        sellerFundsRecipient = new Zorb(address(ZMM));
        operator = new Zorb(address(ZMM));
        bidder = new Zorb(address(ZMM));
        otherBidder = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction v1.0
        auctions = new ReserveAuctionV1(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(auctions));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);
        vm.deal(address(otherBidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Bidder swap 50 ETH <> 50 WETH
        vm.prank(address(bidder));
        weth.deposit{value: 50 ether}();

        // otherBidder swap 50 ETH <> 50 WETH
        vm.prank(address(otherBidder));
        weth.deposit{value: 50 ether}();

        // Users approve ReserveAuction module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);
        otherBidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Bidder approve ERC20TransferHelper
        vm.prank(address(bidder));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // otherBidder approve ERC20TransferHelper
        vm.prank(address(otherBidder));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ CREATE AUCTION ------------ ///

    function testGas_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
    }

    function test_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
        (
            address creator,
            address currency,
            address fundsRecipient,
            address buyer,
            address referrer,
            uint16 findersFee,
            uint256 amt,
            uint256 duration,
            uint256 startTime,
            uint256 firstBidTime,
            uint256 reservePrice
        ) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(seller));
        require(currency == address(0));
        require(fundsRecipient == address(sellerFundsRecipient));
        require(buyer == address(0));
        require(referrer == address(0));
        require(findersFee == 1000);
        require(amt == 0);
        require(duration == 1 days);
        require(startTime == 0);
        require(firstBidTime == 0);
        require(reservePrice == 1 ether);
    }

    function test_CreateAuctionAndCancelPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(sellerFundsRecipient), 0);

        sellerFundsRecipient.setApprovalForModule(address(auctions), true);
        vm.startPrank(address(sellerFundsRecipient));
        token.setApprovalForAll(address(erc721TransferHelper), true);
        auctions.createAuction(address(token), 0, 5 days, 12 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
        vm.stopPrank();

        (address creator, , , , , , , uint256 duration, , , uint256 reservePrice) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(sellerFundsRecipient));
        require(duration == 5 days);
        require(reservePrice == 12 ether);
    }

    function testFail_MustBeTokenOwnerOrOperator() public {
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
    }

    function testRevert_MustApproveERC721TransferHelper() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.prank(address(seller));
        vm.expectRevert("createAuction must approve ERC721TransferHelper as operator");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
    }

    function testRevert_FindersFeeBPSCannotExceed10000() public {
        vm.prank(address(seller));
        vm.expectRevert("createAuction _findersFeeBps must be less than or equal to 10000");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 10001, address(0), 0);
    }

    function testRevert_SellerFundsRecipientCannotBeZeroAddress() public {
        vm.prank(address(seller));
        vm.expectRevert("createAuction must specify _sellerFundsRecipient");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(0)), 1000, address(0), 0);
    }

    /// ------------ SET AUCTION RESERVE PRICE ------------ ///

    function test_SetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(seller));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);

        (, , , , , , , , , , uint256 reservePrice) = auctions.auctionForNFT(address(token), 0);

        require(reservePrice == 5 ether);
    }

    function testRevert_MustBeOwnerOrOperatorToUpdate() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.expectRevert("setAuctionReservePrice must be seller");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateAuctionDoesNotExist() public {
        vm.expectRevert("setAuctionReservePrice must be seller");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(500);
        vm.prank(address(bidder));
        auctions.createBid{value: 5 ether}(address(token), 0, 5 ether, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("setAuctionReservePrice auction has already started");
        auctions.setAuctionReservePrice(address(token), 0, 20 ether);
    }

    /// ------------ CREATE BID ------------ ///

    function test_CreateFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    function test_SetAuctionStartTimeAfterFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(500);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        (, , , , , , , , , uint256 firstBidTime, ) = auctions.auctionForNFT(address(token), 0);

        require(firstBidTime == 500);
    }

    function test_RefundPreviousBidder() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(500);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        uint256 beforeBalance = address(bidder).balance;

        vm.prank(address(otherBidder));
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));

        uint256 afterBalance = address(bidder).balance;
        require(afterBalance - beforeBalance == 1 ether);
    }

    function test_TransferNFTIntoEscrow() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        require(token.ownerOf(0) == address(auctions));
    }

    function test_ExtendAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        // Start 1 hr auction at 5 minutes block time (projected end 1hr 5min block time)
        vm.warp(5 minutes);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        // Place second bid at 55 minutes (10 min left)
        vm.warp(55 minutes);
        vm.prank(address(otherBidder));
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));

        // However the minimum amount of auction time left after a new bid must always be 15 minutes
        (, , , , , , , uint256 newDuration, , , ) = auctions.auctionForNFT(address(token), 0);

        // So the auction (which prev had 10 min left) gets extended by 5 minutes as a result of the second bid
        require(newDuration == 1 hours + 5 minutes);
    }

    function testRevert_CreatorTokenTransferBeforeFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherBidder), 0);

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_CannotBidOnExpiredAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(2 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.warp(3 hours);

        vm.prank(address(otherBidder));
        vm.expectRevert("createBid auction expired");
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));
    }

    function testRevert_CannotBidOnAuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 2238366608); // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)

        vm.prank(address(bidder));
        vm.expectRevert("createBid auction hasn't started");
        auctions.createBid(address(token), 0, 2 ether, address(finder));
    }

    function testFail_CannotBidOnAuctionNotActive() public {
        auctions.createBid(address(token), 0, 2 ether, address(finder));
    }

    function testRevert_BidMustMeetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(bidder));
        vm.expectRevert("createBid must send at least reservePrice");
        auctions.createBid{value: 0.5 ether}(address(token), 0, 0.5 ether, address(finder));
    }

    function testRevert_BidMustBe10PercentGreaterThanPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.prank(address(otherBidder));
        vm.expectRevert("createBid must send more than 10% of last bid amount");
        auctions.createBid{value: 1.01 ether}(address(token), 0, 1.01 ether, address(finder));
    }

    /// ------------ CANCEL AUCTION ------------ ///

    function test_CancelAuction() public {
        vm.startPrank(address(seller));

        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);
        auctions.cancelAuction(address(token), 0);

        vm.stopPrank();

        (address creator, , , , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(0));
    }

    function testRevert_OnlySellerCanCancel() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.expectRevert("cancelAuction must be token owner or operator");
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(500);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("cancelAuction auction already started");
        auctions.cancelAuction(address(token), 0);
    }

    /// ------------ SETTLE AUCTION ------------ ///

    function test_SettleAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.warp(10 hours);
        vm.prank(address(otherBidder));
        auctions.createBid{value: 5 ether}(address(token), 0, 5 ether, address(finder));

        vm.warp(1 days + 1 hours);
        auctions.settleAuction(address(token), 0);

        require(token.ownerOf(0) == address(otherBidder));
    }

    function testRevert_CannotSettleAuctionNotBegun() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.expectRevert("settleAuction auction hasn't begun");
        auctions.settleAuction(address(token), 0);
    }

    function testRevert_CannotSettleAuctionNotComplete() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0);

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.expectRevert("settleAuction auction hasn't completed");
        auctions.settleAuction(address(token), 0);
    }
}
