// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionListingErc20} from "../../../../../modules/ReserveAuction/Listing/ERC20/ReserveAuctionListingErc20.sol";
import {Zorb} from "../../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../../utils/modules/RoyaltyEngine.sol";
import {TestERC20} from "../../../../utils/tokens/TestERC20.sol";
import {TestERC721} from "../../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../../utils/tokens/WETH.sol";
import {VM} from "../../../../utils/VM.sol";

/// @title ReserveAuctionListingErc20Test
/// @notice Unit Tests for Reserve Auction Listing ERC-20
contract ReserveAuctionListingErc20Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    ReserveAuctionListingErc20 internal auctions;
    TestERC20 internal erc20;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal listingFeeRecipient;
    Zorb internal royaltyRecipient;
    Zorb internal bidder;
    Zorb internal otherBidder;
    Zorb internal protocolFeeRecipient;

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
        bidder = new Zorb(address(ZMM));
        otherBidder = new Zorb(address(ZMM));
        listingFeeRecipient = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));
        protocolFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        erc20 = new TestERC20();
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction Listing ERC-20
        auctions = new ReserveAuctionListingErc20(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(auctions));

        // Set module fee
        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(auctions), address(protocolFeeRecipient), 1);

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);
        vm.deal(address(otherBidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Mint bidder 2^96 ERC-20 tokens
        erc20.mint(address(bidder), 2**96);

        // Bidder swap 50 ETH <> 50 WETH
        vm.prank(address(bidder));
        weth.deposit{value: 50 ether}();

        // otherBidder swap 50 ETH <> 50 WETH
        vm.prank(address(otherBidder));
        weth.deposit{value: 50 ether}();

        // Users approve module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);
        otherBidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Bidder approve ERC20TransferHelper for TestERC20
        vm.prank(address(bidder));
        erc20.approve(address(erc20TransferHelper), 2**96);

        // Bidder approve ERC20TransferHelper for WETH
        vm.prank(address(bidder));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // otherBidder approve ERC20TransferHelper
        vm.prank(address(otherBidder));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    ///                                                          ///
    ///                         CREATE AUCTION                   ///
    ///                                                          ///

    function test_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        (
            address creator,
            address fundsRecipient,
            uint256 reservePrice,
            uint256 highestBid,
            address highestBidder,
            uint256 startTime,
            address currency,
            uint256 firstBidTime,
            address lister,
            uint256 duration,
            uint256 listingFeeBps
        ) = auctions.auctionForNFT(address(token), 0);

        require(creator == address(seller));
        require(reservePrice == 1 ether);
        require(fundsRecipient == address(sellerFundsRecipient));
        require(highestBid == 0 ether);
        require(highestBidder == address(0));
        require(duration == 1 days);
        require(startTime == 0);
        require(currency == address(weth));
        require(firstBidTime == 0);
        require(lister == address(listingFeeRecipient));
        require(listingFeeBps == 1000);
    }

    function test_CreateFutureAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            1 days,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        (, , , , , uint256 startTime, , , , , ) = auctions.auctionForNFT(address(token), 0);

        require(startTime == 1 days);
    }

    function test_CreateAuctionAndCancelPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(sellerFundsRecipient), 0);

        sellerFundsRecipient.setApprovalForModule(address(auctions), true);

        vm.startPrank(address(sellerFundsRecipient));
        token.setApprovalForAll(address(erc721TransferHelper), true);
        auctions.createAuction(
            address(token),
            0,
            5 days,
            12 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );
        vm.stopPrank();

        (address creator, , uint256 reservePrice, , , , , , , uint256 duration, ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(sellerFundsRecipient));
        require(duration == 5 days);
        require(reservePrice == 12 ether);
    }

    function testRevert_MustBeTokenOwnerOrOperator() public {
        vm.expectRevert("ONLY_TOKEN_OWNER_OR_OPERATOR");
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );
    }

    function testRevert_ListingFeeBPSCannotExceed10000() public {
        vm.prank(address(seller));
        vm.expectRevert("INVALID_LISTING_FEE");
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            10001,
            address(listingFeeRecipient)
        );
    }

    function testRevert_MustSpecifySellerFundsRecipient() public {
        vm.prank(address(seller));
        vm.expectRevert("INVALID_FUNDS_RECIPIENT");
        auctions.createAuction(address(token), 0, 1 days, 1 ether, address(0), 0, address(weth), 1000, address(listingFeeRecipient));
    }

    ///                                                          ///
    ///                      UPDATE RESERVE PRICE                ///
    ///                                                          ///

    function test_SetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(seller));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);

        (, , uint256 reservePrice, , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(reservePrice == 5 ether);
    }

    function testRevert_UpdateMustBeSeller() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.expectRevert("ONLY_SELLER");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateAuctionDoesNotExist() public {
        vm.expectRevert("ONLY_SELLER");
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 5 ether);

        vm.prank(address(seller));
        vm.expectRevert("AUCTION_STARTED");
        auctions.setAuctionReservePrice(address(token), 0, 20 ether);
    }

    ///                                                          ///
    ///                         CANCEL AUCTION                   ///
    ///                                                          ///

    function test_CancelAuction() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 minutes);

        auctions.cancelAuction(address(token), 0);
        vm.stopPrank();

        (address creator, , , , , , , , , , ) = auctions.auctionForNFT(address(token), 0);
        require(creator == address(0));
    }

    function testRevert_OnlySellerOrOwnerCanCancel() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.expectRevert("ONLY_SELLER_OR_TOKEN_OWNER");
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.prank(address(seller));
        vm.expectRevert("AUCTION_STARTED");
        auctions.cancelAuction(address(token), 0);
    }

    ///                                                          ///
    ///                           CREATE BID                     ///
    ///                                                          ///

    function test_CreateFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);
    }

    function test_StoreTimeOfFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        (, , , , , , , uint256 firstBidTime, , , ) = auctions.auctionForNFT(address(token), 0);

        require(firstBidTime == 1 hours);
    }

    function test_RefundPreviousBidder() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        uint256 beforeBalance = weth.balanceOf(address(bidder));

        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 2 ether);

        uint256 afterBalance = weth.balanceOf(address(bidder));

        require(afterBalance - beforeBalance == 1 ether);
    }

    function test_TransferNFTIntoEscrow() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);
        require(token.ownerOf(0) == address(auctions));
    }

    function test_ExtendAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 hours,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(5 minutes);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(55 minutes);
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 2 ether);

        (, , , , , , , , , uint256 newDuration, ) = auctions.auctionForNFT(address(token), 0);

        require(newDuration == 1 hours + 5 minutes);
    }

    function testRevert_MustApproveModule() public {
        seller.setApprovalForModule(address(auctions), false);

        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 hours,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(bidder));
        vm.expectRevert("module has not been approved by user");
        auctions.createBid(address(token), 0, 1 ether);
    }

    function testRevert_SellerMustApproveERC721TransferHelper() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 hours,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid(address(token), 0, 1 ether);
    }

    function testRevert_InvalidTransferBeforeFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 hours,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherBidder), 0);

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid(address(token), 0, 1 ether);
    }

    function testRevert_CannotBidOnExpiredAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            10 hours,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(12 hours);

        vm.prank(address(otherBidder));
        vm.expectRevert("AUCTION_OVER");
        auctions.createBid(address(token), 0, 2 ether);
    }

    function testRevert_CannotBidOnAuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            1 days,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(bidder));
        vm.expectRevert("AUCTION_NOT_STARTED");
        auctions.createBid(address(token), 0, 1 ether);
    }

    function testRevert_CannotBidOnNonExistentAuction() public {
        vm.expectRevert("AUCTION_DOES_NOT_EXIST");
        auctions.createBid(address(token), 0, 1 ether);
    }

    function testRevert_BidMustMeetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.prank(address(bidder));
        vm.expectRevert("RESERVE_PRICE_NOT_MET");
        auctions.createBid(address(token), 0, 0.5 ether);
    }

    function testRevert_BidMustBe10PercentGreaterThanPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(1 hours + 1 minutes);

        vm.prank(address(otherBidder));
        vm.expectRevert("MINIMUM_BID_NOT_MET");
        auctions.createBid(address(token), 0, 1.01 ether);
    }

    ///                                                          ///
    ///                         SETTLE AUCTION                   ///
    ///                                                          ///

    function test_SettleAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(10 hours);

        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 5 ether);

        vm.warp(1 days + 1 hours);
        auctions.settleAuction(address(token), 0);

        require(token.ownerOf(0) == address(otherBidder));
    }

    function testRevert_AuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.expectRevert("AUCTION_NOT_STARTED");
        auctions.settleAuction(address(token), 0);
    }

    function testRevert_AuctionNotOver() public {
        vm.prank(address(seller));
        auctions.createAuction(
            address(token),
            0,
            1 days,
            1 ether,
            address(sellerFundsRecipient),
            0,
            address(weth),
            1000,
            address(listingFeeRecipient)
        );

        vm.warp(1 hours);

        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(10 hours);

        vm.expectRevert("AUCTION_NOT_OVER");
        auctions.settleAuction(address(token), 0);
    }
}
