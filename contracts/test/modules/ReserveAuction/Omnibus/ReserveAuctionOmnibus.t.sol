// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionDataStorage, FEATURE_MASK_LISTING_FEE, FEATURE_MASK_FINDERS_FEE, FEATURE_MASK_ERC20_CURRENCY, FEATURE_MASK_TOKEN_GATE, FEATURE_MASK_START_TIME, FEATURE_MASK_RECIPIENT_OR_EXPIRY} from "../../../../modules/ReserveAuction/Omnibus/ReserveAuctionDataStorage.sol";
import {ReserveAuctionOmnibus} from "../../../../modules/ReserveAuction/Omnibus/ReserveAuctionOmnibus.sol";
import {IReserveAuctionOmnibus} from "../../../../modules/ReserveAuction/Omnibus/IReserveAuctionOmnibus.sol";
import {Zorb} from "../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../utils/modules/RoyaltyEngine.sol";
import {TestERC20} from "../../../utils/tokens/TestERC20.sol";
import {TestERC721} from "../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../utils/tokens/WETH.sol";
import {VM} from "../../../utils/VM.sol";

/// @title ReserveAuctionOmnibusTest
/// @notice Unit Tests for Reserve Auction Omnibus
contract ReserveAuctionOmnibusTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    ReserveAuctionOmnibus internal auctions;
    TestERC20 internal erc20;
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
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        erc20 = new TestERC20();
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction Finders ERC-20
        auctions = new ReserveAuctionOmnibus(
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

        // Mint bidder 2^96 ERC-20 tokens
        erc20.mint(address(bidder), 2**96);

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

    /// ------------ CREATE AUCTION ------------ ///

    function test_CreateAuction() public {
        vm.prank(address(seller));

        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                block.timestamp + 1 days,
                2 ether,
                address(token),
                1 days,
                1,
                0,
                address(sellerFundsRecipient),
                uint96(block.timestamp + 3 days),
                address(0x001),
                2,
                0,
                address(erc20),
                address(weth)
            )
        );

        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);

        require(auction.reservePrice == 1 ether);
        require(auction.startTime == block.timestamp + 1 days);
        require(auction.seller == address(seller));
        require(auction.expiry == block.timestamp + 3 days);
        require(auction.currency == address(weth));
        require(auction.duration == 1 days);
        require(
            auction.features ==
                FEATURE_MASK_LISTING_FEE |
                    FEATURE_MASK_FINDERS_FEE |
                    FEATURE_MASK_ERC20_CURRENCY |
                    FEATURE_MASK_TOKEN_GATE |
                    FEATURE_MASK_START_TIME |
                    FEATURE_MASK_RECIPIENT_OR_EXPIRY
        );
        require(auction.finder == address(0));
        require(auction.findersFeeBps == 1);
        require(auction.fundsRecipient == address(sellerFundsRecipient));
        require(auction.ongoingAuction.firstBidTime == 0);
        require(auction.ongoingAuction.highestBidder == address(0));
        require(auction.ongoingAuction.highestBid == 0);
        require(auction.listingFeeRecipient == address(0x001));
        require(auction.listingFeeBps == 2);
        require(auction.tokenGateToken == address(erc20));
        require(auction.tokenGateMinAmount == 2 ether);
    }

    function test_CreateAuctionMinimal() public {
        vm.prank(address(seller));
        auctions.createAuctionMinimal(address(token), 0, 1 ether, 1 days);

        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);

        require(auction.reservePrice == 1 ether);
        require(auction.startTime == 0);
        require(auction.seller == address(seller));
        require(auction.expiry == 0);
        require(auction.currency == address(0));
        require(auction.duration == 1 days);
        require(auction.features == 0);
        require(auction.finder == address(0));
        require(auction.findersFeeBps == 0);
        require(auction.fundsRecipient == address(0));
        require(auction.ongoingAuction.firstBidTime == 0);
        require(auction.ongoingAuction.highestBidder == address(0));
        require(auction.ongoingAuction.highestBid == 0);
        require(auction.listingFeeRecipient == address(0));
        require(auction.listingFeeBps == 0);
        require(auction.tokenGateToken == address(0));
        require(auction.tokenGateMinAmount == 0 ether);
    }

    function test_CreateAuctionAndCancelPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                1000,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(sellerFundsRecipient), 0);

        sellerFundsRecipient.setApprovalForModule(address(auctions), true);

        vm.startPrank(address(sellerFundsRecipient));
        token.setApprovalForAll(address(erc721TransferHelper), true);
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                12 ether,
                0,
                0,
                address(token),
                5 days,
                1000,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.stopPrank();

        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        require(auction.seller == address(sellerFundsRecipient));
        require(auction.duration == 5 days);
        require(auction.reservePrice == 12 ether);
    }

    function testRevert_MustBeTokenOwnerOrOperator() public {
        vm.expectRevert(abi.encodeWithSignature("NOT_TOKEN_OWNER_OR_OPERATOR()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                1000,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
    }

    function testRevert_CreateAuctionModuleOrTransferHelperNotApproved() public {
        vm.startPrank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);
        vm.expectRevert(abi.encodeWithSignature("TRANSFER_HELPER_NOT_APPROVED()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                block.timestamp + 1 days,
                2 ether,
                address(token),
                1 days,
                1,
                0,
                address(sellerFundsRecipient),
                uint96(block.timestamp + 3 days),
                address(0x001),
                2,
                0,
                address(erc20),
                address(weth)
            )
        );

        token.setApprovalForAll(address(erc721TransferHelper), true);
        seller.setApprovalForModule(address(auctions), false);
        vm.expectRevert(abi.encodeWithSignature("MODULE_NOT_APPROVED()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                block.timestamp + 1 days,
                2 ether,
                address(token),
                1 days,
                1,
                0,
                address(sellerFundsRecipient),
                uint96(block.timestamp + 3 days),
                address(0x001),
                2,
                0,
                address(erc20),
                address(weth)
            )
        );
        vm.stopPrank();
    }

    function testRevert_FindersFeePlusListingFeeCannotExceed10000() public {
        vm.prank(address(seller));
        vm.expectRevert(abi.encodeWithSignature("INVALID_FEES()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                5000,
                0,
                address(sellerFundsRecipient),
                0,
                address(sellerFundsRecipient),
                5001,
                0,
                address(0),
                address(weth)
            )
        );
    }

    function testRevert_TimeBufferMustBeValid() public {
        vm.startPrank(address(seller));
        vm.expectRevert(abi.encodeWithSignature("INVALID_TIME_BUFFER()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                3 hours,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.expectRevert(abi.encodeWithSignature("INVALID_TIME_BUFFER()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                1 seconds,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.stopPrank();
    }

    function testRevert_PercentIncrementMustBeValid() public {
        vm.prank(address(seller));
        vm.expectRevert(abi.encodeWithSignature("INVALID_PERCENT_INCREMENT()"));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                51,
                address(0),
                address(weth)
            )
        );
    }

    /// ------------ SET AUCTION RESERVE PRICE ------------ ///

    function test_SetReservePrice() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
        vm.stopPrank();
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        require(auction.reservePrice == 5 ether);
    }

    function test_SetReservePriceOperator() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        token.setApprovalForAll(address(sellerFundsRecipient), true);
        vm.stopPrank();
        vm.prank(address(sellerFundsRecipient));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        require(auction.reservePrice == 5 ether);
    }

    function testRevert_UpdateMustBeTokenOwnerOrOperator() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.expectRevert(abi.encodeWithSignature("NOT_TOKEN_OWNER_OR_OPERATOR()"));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateAuctionDoesNotExist() public {
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        assertEq(auction.seller, address(0));
        vm.prank(token.ownerOf(0));
        vm.expectRevert(abi.encodeWithSignature("AUCTION_DOES_NOT_EXIST()"));
        auctions.setAuctionReservePrice(address(token), 0, 5 ether);
    }

    function testRevert_CannotUpdateActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 5 ether, address(finder));
        vm.prank(address(seller));
        vm.expectRevert(abi.encodeWithSignature("AUCTION_STARTED()"));
        auctions.setAuctionReservePrice(address(token), 0, 20 ether);
    }

    /// ------------ CANCEL AUCTION ------------ ///

    function test_CancelAuction() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 minutes);
        auctions.cancelAuction(address(token), 0);
        vm.stopPrank();
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        require(auction.seller == address(0));
    }

    function testRevert_OnlySellerOrOperatorCanCancelValidAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.expectRevert(abi.encodeWithSignature("NOT_TOKEN_OWNER_OR_OPERATOR()"));
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_PublicCanCancelInalidAuction() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        token.safeTransferFrom(address(seller), address(sellerFundsRecipient), 0);
        vm.stopPrank();
        auctions.cancelAuction(address(token), 0);
    }

    function testRevert_CannotCancelActiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.prank(address(seller));
        vm.expectRevert(abi.encodeWithSignature("AUCTION_STARTED()"));
        auctions.cancelAuction(address(token), 0);
    }

    /// ------------ CREATE BID ------------ ///

    function test_CreateFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.prank(address(bidder));
        vm.warp(1 hours);

        auctions.createBid(address(token), 0, 1 ether, address(finder));
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        assertEq(auction.ongoingAuction.highestBid, 1 ether);
        assertEq(auction.ongoingAuction.highestBidder, address(bidder));
        assertEq(auction.ongoingAuction.firstBidTime, 1 hours);
    }

    function test_RefundPreviousBidder() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        uint256 beforeBalance = weth.balanceOf(address(bidder));
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 2 ether, address(finder));
        uint256 afterBalance = weth.balanceOf(address(bidder));
        require(afterBalance - beforeBalance == 1 ether);
    }

    function test_TransferNFTIntoEscrow() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        require(token.ownerOf(0) == address(auctions));
    }

    function test_ExtendAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(5 minutes);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(55 minutes);
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 2 ether, address(finder));
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        require(auction.duration == 1 hours + 5 minutes);
    }

    function test_ExtendAuctionWithCustomBuffer() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                3 hours,
                0,
                1 hours,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(10 minutes);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(2 hours + 20 minutes);
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 2 ether, address(finder));
        ReserveAuctionDataStorage.FullAuction memory auction = auctions.getFullAuction(address(token), 0);
        assertEq(auction.duration, 3 hours + 10 minutes);
    }

    function testRevert_MustApproveModule() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        seller.setApprovalForModule(address(auctions), false);
        vm.stopPrank();

        vm.prank(address(bidder));
        vm.expectRevert("module has not been approved by user");
        auctions.createBid(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_SellerMustApproveERC721TransferHelper() public {
        vm.startPrank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        token.setApprovalForAll(address(erc721TransferHelper), false);
        vm.stopPrank();

        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_InvalidTransferBeforeFirstBid() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherBidder), 0);
        vm.prank(address(bidder));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        auctions.createBid(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_CannotBidOnExpiredAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                10 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(12 hours);
        vm.prank(address(otherBidder));
        vm.expectRevert(abi.encodeWithSignature("AUCTION_OVER()"));
        auctions.createBid(address(token), 0, 2 ether, address(finder));
    }

    function testRevert_CannotBidOnAuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                block.timestamp + 1 days,
                0,
                address(token),
                10 hours,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.prank(address(bidder));
        vm.expectRevert(abi.encodeWithSignature("AUCTION_NOT_STARTED()"));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_CannotBidOnNonExistentAuction() public {
        vm.expectRevert(abi.encodeWithSignature("AUCTION_DOES_NOT_EXIST()"));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
    }

    function testRevert_BidMustMeetReservePrice() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.prank(address(bidder));
        vm.expectRevert(abi.encodeWithSignature("RESERVE_PRICE_NOT_MET()"));
        auctions.createBid(address(token), 0, 0.5 ether, address(finder));
    }

    function testRevert_BidMustBeDefaultPercentGreaterThanPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(1 hours + 1 minutes);
        vm.startPrank(address(otherBidder));
        vm.expectRevert(abi.encodeWithSignature("MINIMUM_BID_NOT_MET()"));
        auctions.createBid(address(token), 0, 1.01 ether, address(finder));
        auctions.createBid(address(token), 0, 1.10 ether, address(finder));
        vm.stopPrank();
    }

    function testRevert_BidMustBeCustomPercentGreaterThanPrevious() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                15,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(1 hours + 1 minutes);
        vm.startPrank(address(otherBidder));
        vm.expectRevert(abi.encodeWithSignature("MINIMUM_BID_NOT_MET()"));
        auctions.createBid(address(token), 0, 1.10 ether, address(finder));
        auctions.createBid(address(token), 0, 1.15 ether, address(finder));
        vm.stopPrank();
    }

    /// ------------ SETTLE AUCTION ------------ ///

    function test_SettleAuction() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(10 hours);
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 5 ether, address(finder));
        vm.warp(1 days + 1 hours);
        auctions.settleAuction(address(token), 0);
        require(token.ownerOf(0) == address(otherBidder));
    }

    function testRevert_AuctionNotStarted() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.expectRevert(abi.encodeWithSignature("AUCTION_NOT_STARTED()"));
        auctions.settleAuction(address(token), 0);
    }

    function testRevert_AuctionNotOver() public {
        vm.prank(address(seller));
        auctions.createAuction(
            IReserveAuctionOmnibus.CreateAuctionParameters(
                0,
                1 ether,
                0,
                0,
                address(token),
                1 days,
                0,
                0,
                address(sellerFundsRecipient),
                0,
                address(0),
                0,
                0,
                address(0),
                address(weth)
            )
        );
        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether, address(finder));
        vm.warp(10 hours);
        vm.expectRevert(abi.encodeWithSignature("AUCTION_NOT_OVER()"));
        auctions.settleAuction(address(token), 0);
    }
}
