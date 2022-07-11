// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {DutchAuctionV1} from "../../../../modules/DutchAuction/V1/DutchAuctionV1.sol";
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

/// @title DutchAuctionV1Test
/// @notice Unit Tests for Dutch Auction v1.0
contract DutchAuctionV1Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    DutchAuctionV1 internal auctions;
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
        auctions = new DutchAuctionV1(
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
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
    }

    function test_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
        (
            address creator,
            address currency,
            address fundsRecipient,
            address referrer,
            uint16 findersFee,
            uint256 startPrice,
            uint256 endPrice,
            uint256 startTime,
            uint256 duration
        ) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(seller));
        require(currency == address(0));
        require(fundsRecipient == address(sellerFundsRecipient));
        require(referrer == address(0));
        require(findersFee == 1000);
        require(startPrice == 1 ether);
        require(endPrice == 0.2 ether);
        require(startTime == 0);
        require(duration == 1 days);
    }

    function test_CreateAuctionAndCancelPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(sellerFundsRecipient), 0);

        sellerFundsRecipient.setApprovalForModule(address(auctions), true);
        vm.startPrank(address(sellerFundsRecipient));
        token.setApprovalForAll(address(erc721TransferHelper), true);
        auctions.createAuction(address(token), 0, 5 ether, 2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
        vm.stopPrank();

        (address creator, , , , , uint256 startPrice, uint256 endPrice, , ) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(sellerFundsRecipient));
        require(startPrice == 5 ether);
        require(endPrice == 2 ether);
    }

    function testFail_MustBeTokenOwnerOrOperator() public {
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
    }

    function testRevert_MustApproveERC721TransferHelper() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.prank(address(seller));
        vm.expectRevert("createAuction must approve ERC721TransferHelper as operator");
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
    }

    function testRevert_FindersFeeBPSCannotExceed10000() public {
        vm.prank(address(seller));
        vm.expectRevert("createAuction _findersFeeBps must be less than or equal to 10000");
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 10001, address(0), 0, 0);
    }

    function testRevert_SellerFundsRecipientCannotBeZeroAddress() public {
        vm.prank(address(seller));
        vm.expectRevert("createAuction must specify _sellerFundsRecipient");
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(0)), 1000, address(0), 0, 0);
    }

    function testRevert_EndpriceCannotExceedStartPrice() public {
        vm.prank(address(seller));
        vm.expectRevert("createAuction _startPrice must be greater than _endPrice");
        auctions.createAuction(address(token), 0, 1 ether, 2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
    }

    /// ------------ SET AUCTION PRICES ------------ ///

    function test_SetPrices() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 ether,
            0.2 ether,
            payable(address(sellerFundsRecipient)),
            1000,
            address(0),
            block.timestamp + 1 hours,
            0
        );

        vm.prank(address(seller));
        auctions.setAuctionPrices(address(token), 0, 5 ether, 2 ether);

        (, , , , , uint256 startPrice, uint256 endPrice, , ) = auctions.auctionForNFT(address(token), 0);

        require(startPrice == 5 ether && endPrice == 2 ether);
    }

    function testRevert_MustBeOwnerOrOperatorToUpdate() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 ether,
            0.2 ether,
            payable(address(sellerFundsRecipient)),
            1000,
            address(0),
            block.timestamp + 1 hours,
            0
        );

        vm.expectRevert("setAuctionPrices must be seller");
        auctions.setAuctionPrices(address(token), 0, 5 ether, 2 ether);
    }

    function testRevert_CannotUpdateAuctionDoesNotExist() public {
        vm.expectRevert("setAuctionPrices must be seller");
        auctions.setAuctionPrices(address(token), 0, 5 ether, 2 ether);
    }

    function testRevert_CannotUpdateEndpriceExceedingStartPrice() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 ether,
            0.2 ether,
            payable(address(sellerFundsRecipient)),
            1000,
            address(0),
            block.timestamp + 1 hours,
            0
        );

        vm.expectRevert("setAuctionPrices _startPrice must be greater than _endPrice");
        vm.prank(address(seller));
        auctions.setAuctionPrices(address(token), 0, 2 ether, 5 ether);
    }

    function testRevert_CannotUpdateActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.expectRevert("setAuctionPrices auction startTime must be future block");
        vm.prank(address(seller));
        auctions.setAuctionPrices(address(token), 0, 5 ether, 2 ether);
    }

    /// ------------ CREATE BID ------------ ///

    function test_CreateFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        require(token.ownerOf(0) == address(bidder));
    }

    function test_CreateDelayedBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 2 hours);

        vm.warp(1 hours);
        uint256 price = auctions.getPrice(address(token), 0);

        vm.prank(address(bidder));
        auctions.createBid{value: price}(address(token), 0, price, address(finder));

        require(token.ownerOf(0) == address(bidder));
    }

    function testRevert_CreatorTokenTransferBeforeFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherBidder), 0);

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_CannotBidOnExpiredAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 1 hours);

        vm.warp(2 hours);

        vm.prank(address(otherBidder));
        vm.expectRevert("createBid auction expired");
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));
    }

    function testRevert_CannotBidOnAuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 2238366608, 0); // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)

        vm.prank(address(bidder));
        vm.expectRevert("createBid auction hasn't started");
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));
    }

    function testFail_CannotBidOnAuctionNotActive() public {
        auctions.createBid{value: 2 ether}(address(token), 0, 2 ether, address(finder));
    }

    function testRevert_BidMustMeetPrice() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(bidder));
        vm.expectRevert("createBid must send more than current price");
        auctions.createBid{value: 0.5 ether}(address(token), 0, 0.5 ether, address(finder));
    }

    function testRevert_CannotBidOnAuctionEnded() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 1 hours);

        vm.warp(2 hours);
        vm.prank(address(bidder));
        vm.expectRevert("createBid auction expired");
        auctions.createBid{value: 0.5 ether}(address(token), 0, 0.5 ether, address(finder));
    }

    function testRevert_CannotBidAfterInitalBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 1 hours);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.prank(address(otherBidder));
        vm.expectRevert("createBid auction doesn't exist");
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    /// ------------ CANCEL AUCTION ------------ ///

    function test_CancelAuction() public {
        vm.startPrank(address(seller));

        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);
        auctions.cancelAuction(address(token), 0);

        vm.stopPrank();

        (address creator, , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(0));
    }

    function test_CancelAuctionEnded() public {
        vm.startPrank(address(seller));

        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 1 hours);
        vm.warp(2 hours);
        auctions.cancelAuction(address(token), 0);

        vm.stopPrank();

        (address creator, , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(0));
    }

    function testRevert_OnlySellerCanCancel() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.expectRevert("cancelAuction must be token owner or operator");
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.warp(500);

        vm.prank(address(seller));
        vm.expectRevert("cancelAuction auction currently in progress");
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelAfterBid() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("cancelAuction auction doesn't exist");
        auctions.cancelAuction(address(token), 0);
    }

    function testFail_CannotCancelAuctionNotActive() public {
        auctions.cancelAuction(address(token), 0);
    }
}
