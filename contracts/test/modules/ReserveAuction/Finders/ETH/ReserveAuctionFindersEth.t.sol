// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionFindersEth} from "../../../../../modules/ReserveAuction/Finders/ETH/ReserveAuctionFindersEth.sol";
import {Zorb} from "../../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../../utils/modules/RoyaltyEngine.sol";
import {TestERC721} from "../../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../../utils/tokens/WETH.sol";
import {VM} from "../../../../utils/VM.sol";

/// @title ReserveAuctionFindersEthTest
/// @notice Unit Tests for Reserve Auction Finders ETH
contract ReserveAuctionFindersEthTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    ReserveAuctionFindersEth internal auctions;

    TestERC721 internal token;
    WETH internal weth;
    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal bidder;
    Zorb internal otherBidder;
    Zorb internal finder;
    Zorb internal lister;
    Zorb internal royaltyRecipient;

    function setUp() public {
        // Cheatcodes
        vm = VM(HEVM_ADDRESS);

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
        lister = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction Finders ETH
        auctions = new ReserveAuctionFindersEth(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(auctions));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);
        vm.deal(address(otherBidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Users approve module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);
        otherBidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    ///                                                          ///
    ///                         CREATE AUCTION                   ///
    ///                                                          ///

    function test_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        (
            address creator,
            uint256 reservePrice,
            address fundsRecipient,
            uint256 highestBid,
            address highestBidder,
            uint256 duration,
            uint256 startTime,
            address highestBidfinder,
            uint256 firstBidTime,
            uint256 findersFeeBps
        ) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(seller));
        require(reservePrice == 1 ether);
        require(fundsRecipient == address(sellerFundsRecipient));
        require(highestBid == 0 ether);
        require(highestBidder == address(0));
        require(duration == 1 days);
        require(startTime == 0);
        require(highestBidfinder == address(0));
        require(findersFeeBps == 1000);
        require(firstBidTime == 0);
    }

    function test_CreateFutureAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 1 days, 1000);

        (, , , , , , uint256 startTime, , , ) = auctions.auctionForNFT(address(token), 0);
        require(startTime == 1 days);
    }

    function test_CreateAuctionAndCancelPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(sellerFundsRecipient), 0);

        sellerFundsRecipient.setApprovalForModule(address(auctions), true);

        vm.startPrank(address(sellerFundsRecipient));
        token.setApprovalForAll(address(erc721TransferHelper), true);
        auctions.createAuction(address(token), 0, 5 days, 12 ether, address(sellerFundsRecipient), 0, 1000);
        vm.stopPrank();

        (address creator, uint256 reservePrice, , , , uint256 duration, , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(sellerFundsRecipient));
        require(duration == 5 days);
        require(reservePrice == 12 ether);
    }

    function testRevert_MustBeTokenOwnerOrOperator() public {
        vm.expectRevert("ONLY_TOKEN_OWNER_OR_OPERATOR");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);
    }

    function testRevert_FindersFeeBPSCannotExceed10000() public {
        vm.prank(address(seller));
        vm.expectRevert("INVALID_FINDERS_FEE");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 10001);
    }

    function testRevert_MustSpecifySellerFundsRecipient() public {
        vm.prank(address(seller));
        vm.expectRevert("INVALID_FUNDS_RECIPIENT");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(0), 0, 1000);
    }

    ///                                                          ///
    ///                      UPDATE RESERVE PRICE                ///
    ///                                                          ///

    function test_SetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(seller));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);

        (, uint256 reservePrice, , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(reservePrice == 5 ether);
    }

    function testRevert_UpdateMustBeSeller() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.expectRevert("ONLY_SELLER");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateAuctionDoesNotExist() public {
        vm.expectRevert("ONLY_SELLER");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 5 ether}(address(token), 0, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("AUCTION_STARTED");
        auctions.setAuctionReservePrice(address(token), 0, 20 ether);
    }

    ///                                                          ///
    ///                         CANCEL AUCTION                   ///
    ///                                                          ///

    function test_CancelAuction() public {
        vm.startPrank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 minutes);

        auctions.cancelAuction(address(token), 0);
        vm.stopPrank();

        (address creator, , , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(0));
    }

    function testRevert_OnlySellerOrOwnerCanCancel() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.expectRevert("ONLY_SELLER_OR_TOKEN_OWNER");
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("AUCTION_STARTED");
        auctions.cancelAuction(address(token), 0);
    }

    ///                                                          ///
    ///                           CREATE BID                     ///
    ///                                                          ///

    function test_CreateFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
    }

    function test_StoreTimeOfFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        (, , , , , , , , uint256 firstBidTime, ) = auctions.auctionForNFT(address(token), 0);
        require(firstBidTime == 1 hours);
    }

    function test_RefundPreviousBidder() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
        uint256 beforeBalance = address(bidder).balance;

        vm.prank(address(otherBidder));
        auctions.createBid{value: 2 ether}(address(token), 0, address(finder));

        uint256 afterBalance = address(bidder).balance;

        require(afterBalance - beforeBalance == 1 ether);
    }

    function test_TransferNFTIntoEscrow() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
        require(token.ownerOf(0) == address(auctions));
    }

    function test_ExtendAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(5 minutes);
        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.warp(55 minutes);
        vm.prank(address(otherBidder));
        auctions.createBid{value: 2 ether}(address(token), 0, address(finder));

        (, , , , , uint256 newDuration, , , , ) = auctions.auctionForNFT(address(token), 0);

        require(newDuration == 1 hours + 5 minutes);
    }

    function testRevert_MustApproveModule() public {
        seller.setApprovalForModule(address(auctions), false);

        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(bidder));
        vm.expectRevert("module has not been approved by user");
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
    }

    function testRevert_SellerMustApproveERC721TransferHelper() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
    }

    function testRevert_InvalidTransferBeforeFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 hours, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherBidder), 0);

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
    }

    function testRevert_CannotBidOnExpiredAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 10 hours, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.warp(12 hours);

        vm.prank(address(otherBidder));
        vm.expectRevert("AUCTION_OVER");
        auctions.createBid{value: 2 ether}(address(token), 0, address(finder));
    }

    function testRevert_CannotBidOnAuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 1 days, 1000);

        vm.prank(address(bidder));
        vm.expectRevert("AUCTION_NOT_STARTED");
        auctions.createBid(address(token), 0, address(finder));
    }

    function testRevert_CannotBidOnAuctionNotActive() public {
        vm.expectRevert("AUCTION_DOES_NOT_EXIST");
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));
    }

    function testRevert_BidMustMeetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.prank(address(bidder));
        vm.expectRevert("RESERVE_PRICE_NOT_MET");
        auctions.createBid{value: 0.5 ether}(address(token), 0, address(finder));
    }

    function testRevert_BidMustBe10PercentGreaterThanPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.warp(1 hours + 1 minutes);

        vm.prank(address(otherBidder));
        vm.expectRevert("MINIMUM_BID_NOT_MET");
        auctions.createBid{value: 1.01 ether}(address(token), 0, address(finder));
    }

    ///                                                          ///
    ///                         SETTLE AUCTION                   ///
    ///                                                          ///

    function test_SettleAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.warp(10 hours);

        vm.prank(address(otherBidder));
        auctions.createBid{value: 5 ether}(address(token), 0, address(finder));

        vm.warp(1 days + 1 hours);
        auctions.settleAuction(address(token), 0);

        require(token.ownerOf(0) == address(otherBidder));
    }

    function testRevert_AuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.expectRevert("AUCTION_NOT_STARTED");
        auctions.settleAuction(address(token), 0);
    }

    function testRevert_AuctionNotOver() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(sellerFundsRecipient), 0, 1000);

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, address(finder));

        vm.warp(10 hours);

        vm.expectRevert("AUCTION_NOT_OVER");
        auctions.settleAuction(address(token), 0);
    }
}
