// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../../modules/VariableSupplyAuction/VariableSupplyAuction.sol";
import "../../../modules/VariableSupplyAuction/temp-MockERC721Drop.sol";

import {Zorb} from "../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../utils/modules/RoyaltyEngine.sol";
import {TestERC721} from "../../utils/tokens/TestERC721.sol";
import {WETH} from "../../utils/tokens/WETH.sol";
import {VM} from "../../utils/VM.sol";

/// @title VariableSupplyAuctionTest
/// @notice Unit Tests for Variable Supply Auctions
contract VariableSupplyAuctionTest is Test {
    //

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    VariableSupplyAuction internal auctions;
    ERC721Drop internal drop;
    DummyMetadataRenderer internal dummyRenderer;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal finder;
    Zorb internal royaltyRecipient;
    Zorb internal bidder1;
    Zorb internal bidder2;
    Zorb internal bidder3;
    Zorb internal bidder4;
    Zorb internal bidder5;
    Zorb internal bidder6;
    Zorb internal bidder7;
    Zorb internal bidder8;
    Zorb internal bidder9;
    Zorb internal bidder10;
    Zorb internal bidder11;
    Zorb internal bidder12;
    Zorb internal bidder13;
    Zorb internal bidder14;
    Zorb internal bidder15;

    string internal constant salt1 = "setec astronomy";
    string internal constant salt2 = "too many secrets";
    string internal constant salt3 = "cray tomes on set";
    string internal constant salt4 = "o no my tesseract";
    string internal constant salt5 = "ye some contrast";
    string internal constant salt6 = "a tron ecosystem";
    string internal constant salt7 = "stonecasty rome";
    string internal constant salt8 = "coy teamster son";
    string internal constant salt9 = "cyanometer toss";
    string internal constant salt10 = "cementatory sos";
    string internal constant salt11 = "my cotoneasters";
    string internal constant salt12 = "ny sec stateroom";
    string internal constant salt13 = "oc attorney mess";
    string internal constant salt14 = "my cots earstones";
    string internal constant salt15 = "easternmost coy";

    uint32 internal constant TIME0 = 1_666_000_000; // now-ish, Autumn 2022

    function setUp() public {
        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create users
        seller = new Zorb(address(ZMM));
        sellerFundsRecipient = new Zorb(address(ZMM));
        operator = new Zorb(address(ZMM));
        bidder1 = new Zorb(address(ZMM));
        bidder2 = new Zorb(address(ZMM));
        bidder3 = new Zorb(address(ZMM));
        bidder4 = new Zorb(address(ZMM));
        bidder5 = new Zorb(address(ZMM));
        bidder6 = new Zorb(address(ZMM));
        bidder7 = new Zorb(address(ZMM));
        bidder8 = new Zorb(address(ZMM));
        bidder9 = new Zorb(address(ZMM));
        bidder10 = new Zorb(address(ZMM));
        bidder11 = new Zorb(address(ZMM));
        bidder12 = new Zorb(address(ZMM));
        bidder13 = new Zorb(address(ZMM));
        bidder14 = new Zorb(address(ZMM));
        bidder15 = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(sellerFundsRecipient), 100 ether);
        vm.deal(address(bidder1), 100 ether);
        vm.deal(address(bidder2), 100 ether);
        vm.deal(address(bidder3), 100 ether);
        vm.deal(address(bidder4), 100 ether);
        vm.deal(address(bidder5), 100 ether);
        vm.deal(address(bidder6), 100 ether);
        vm.deal(address(bidder7), 100 ether);
        vm.deal(address(bidder8), 100 ether);
        vm.deal(address(bidder9), 100 ether);
        vm.deal(address(bidder10), 100 ether);
        vm.deal(address(bidder11), 100 ether);
        vm.deal(address(bidder12), 100 ether);
        vm.deal(address(bidder13), 100 ether);
        vm.deal(address(bidder14), 100 ether);
        vm.deal(address(bidder15), 100 ether);

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        drop = new ERC721Drop();
        dummyRenderer = new DummyMetadataRenderer();
        drop.initialize({
            _contractName: "Test Mutant Ninja Turtles",
            _contractSymbol: "TMNT",
            _initialOwner: address(seller),
            _fundsRecipient: payable(sellerFundsRecipient),
            _editionSize: 1, // to be updated by seller during settle phase
            _royaltyBPS: 1000,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: "",
            _salesConfig: ERC721Drop.SalesConfiguration({
                publicSaleStart: 0,
                publicSaleEnd: 0,
                presaleStart: 0,
                presaleEnd: 0,
                publicSalePrice: 0,
                maxSalePurchasePerAddress: 0,
                presaleMerkleRoot: bytes32(0)
            })
        });
        weth = new WETH();

        // Deploy Variable Supply Auction module
        auctions = new VariableSupplyAuction(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(auctions));

        // Grant auction minter role on drop contract
        vm.prank(address(seller));
        drop.grantRole(drop.MINTER_ROLE(), address(auctions));

        // Users approve module
        seller.setApprovalForModule(address(auctions), true);
        bidder1.setApprovalForModule(address(auctions), true);
        bidder2.setApprovalForModule(address(auctions), true);
        bidder3.setApprovalForModule(address(auctions), true);
        bidder4.setApprovalForModule(address(auctions), true);
        bidder5.setApprovalForModule(address(auctions), true);
        bidder6.setApprovalForModule(address(auctions), true);
        bidder7.setApprovalForModule(address(auctions), true);
        bidder8.setApprovalForModule(address(auctions), true);
        bidder9.setApprovalForModule(address(auctions), true);
        bidder10.setApprovalForModule(address(auctions), true);
        bidder11.setApprovalForModule(address(auctions), true);
        bidder12.setApprovalForModule(address(auctions), true);
        bidder13.setApprovalForModule(address(auctions), true);
        bidder14.setApprovalForModule(address(auctions), true);
        bidder15.setApprovalForModule(address(auctions), true);

        // TODO determine pattern for seller approving module to set edition size and mint

        // Seller approve ERC721TransferHelper
        // vm.prank(address(seller));
        // token.setApprovalForAll(address(erc721TransferHelper), true);

        // Start from this time
        vm.warp(TIME0);
    }

    function test_DropInitial() public {
        assertEq(drop.name(), "Test Mutant Ninja Turtles");
        assertEq(drop.symbol(), "TMNT");

        assertEq(drop.owner(), address(seller));
        assertEq(drop.getRoleMember(drop.MINTER_ROLE(), 0), address(auctions));

        (
            IMetadataRenderer renderer,
            uint64 editionSize,
            uint16 royaltyBPS,
            address payable fundsRecipient
        ) = drop.config();

        assertEq(address(renderer), address(dummyRenderer));
        assertEq(editionSize, 1);
        assertEq(royaltyBPS, 1000);
        assertEq(fundsRecipient, payable(sellerFundsRecipient));
    }

    /*//////////////////////////////////////////////////////////////
                        EIP-165
    //////////////////////////////////////////////////////////////*/

    function test_SupportsInterface() public {
        assertTrue(auctions.supportsInterface(0x01ffc9a7)); // EIP-165
        assertTrue(auctions.supportsInterface(type(IVariableSupplyAuction).interfaceId));
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE AUCTION
    //////////////////////////////////////////////////////////////*/

    function testGas_CreateAuction() public {
        // Note this same basic setup is applied to other tests via the setupBasicAuction modifier
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    function test_CreateAuction_WhenInstant() public setupBasicAuction {
        (
            address sellerStored,
            uint256 minimumViableRevenue,
            address sellerFundsRecipientStored,
            uint256 startTime,
            uint256 endOfBidPhase,
            uint256 endOfRevealPhase,
            uint256 endOfSettlePhase,
            uint96 totalBalance,
            uint96 settledRevenue,
            uint96 settledPricePoint,
            uint96 settledEditionSize
        ) = auctions.auctionForDrop(address(drop));

        assertEq(sellerStored, address(seller));
        assertEq(minimumViableRevenue, 10 ether);
        assertEq(sellerFundsRecipientStored, address(sellerFundsRecipient));
        assertEq(startTime, uint32(block.timestamp));
        assertEq(endOfBidPhase, uint32(block.timestamp + 3 days));
        assertEq(endOfRevealPhase, uint32(block.timestamp + 3 days + 2 days));
        assertEq(endOfSettlePhase, uint32(block.timestamp + 3 days + 2 days + 1 days));
        assertEq(totalBalance, uint96(0));
        assertEq(settledRevenue, uint96(0));
        assertEq(settledPricePoint, uint96(0));
        assertEq(settledEditionSize, uint96(0));
    }

    function test_CreateAuction_WhenFuture() public {
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: 1 days,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        (
            ,
            ,
            ,
            uint32 startTime,
            uint32 endOfBidPhase,
            uint32 endOfRevealPhase,
            uint32 endOfSettlePhase,
            ,
            ,
            ,
        ) = auctions.auctionForDrop(address(drop));

        assertEq(startTime, 1 days);
        assertEq(endOfBidPhase, 1 days + 3 days);
        assertEq(endOfRevealPhase, 1 days + 3 days + 2 days);
        assertEq(endOfSettlePhase, 1 days + 3 days + 2 days + 1 days);
    }

    function testEvent_createAuction() public {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 0,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        vm.expectEmit(false, false, false, false);
        emit AuctionCreated(address(drop), auction);

        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    function testRevert_CreateAuction_WhenDropHasLiveAuction() public setupBasicAuction {
        vm.expectRevert(IVariableSupplyAuction.Auction_AlreadyLiveAuctionForDrop.selector);

        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    function testRevert_CreateAuction_WhenDidNotSpecifySellerFundsRecipient() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_InvalidFundsRecipient.selector);

        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(0),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    // TODO add tests for multiple valid auctions at once

    // TODO add tests that exercise other actions for auctions that don't start instantly

    /*//////////////////////////////////////////////////////////////
                        CANCEL AUCTION
    //////////////////////////////////////////////////////////////*/

    function test_CancelAuction_WhenNoBidsPlacedYet() public setupBasicAuction {
        // precondition check
        (
            address sellerStored,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,   
        ) = auctions.auctionForDrop(address(drop));
        assertEq(sellerStored, address(seller));

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));

        // Then auction has been deleted
        (
            sellerStored,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = auctions.auctionForDrop(address(drop));
        assertEq(sellerStored, address(0));
    }

    function test_CancelAuction_WhenInSettlePhaseButMinimumViableRevenueNotMet() public setupBasicAuction {        
        bytes32 commitment1 = _genSealedBid(1 ether, salt1);
        bytes32 commitment2 = _genSealedBid(2 ether, salt2);
        bytes32 commitment3 = _genSealedBid(3 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 3 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 5 ether}(address(drop), commitment3);        

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 3 ether, salt3);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop)); // first, consider the settle outcomes

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));

        // Then auction has been deleted
        (
            address sellerStored,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = auctions.auctionForDrop(address(drop));
        assertEq(sellerStored, address(0));
    }

    function testEvent_CancelAuction() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 0,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionCanceled(address(drop), auction);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenNotSeller() public setupBasicAuction {
        vm.expectRevert(IVariableSupplyAuction.Access_OnlySeller.selector);

        vm.prank(address(bidder1));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenInSettlePhaseButHaveNotCalculatedSettleOutcomesYet() public setupBasicAuction {        
        bytes32 commitment1 = _genSealedBid(10 ether, salt1);
        bytes32 commitment2 = _genSealedBid(2 ether, salt2);
        bytes32 commitment3 = _genSealedBid(3 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 10 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 3 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 5 ether}(address(drop), commitment3);        

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 10 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 3 ether, salt3);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.expectRevert(IVariableSupplyAuction.Seller_CannotCancelAuctionDuringSettlePhaseWithoutCalculatingOutcomes.selector);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenInSettlePhaseAndMinimumViableRevenueWasMet() public setupBasicAuction {        
        bytes32 commitment1 = _genSealedBid(10 ether, salt1);
        bytes32 commitment2 = _genSealedBid(2 ether, salt2);
        bytes32 commitment3 = _genSealedBid(3 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 10 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 3 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 5 ether}(address(drop), commitment3);        

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 10 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 3 ether, salt3);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));

        vm.expectRevert(IVariableSupplyAuction.Seller_CannotCancelAuctionWithViablePricePoint.selector);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenBidAlreadyPlaced() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.expectRevert(IVariableSupplyAuction.Seller_CannotCancelAuctionWithBidsBeforeSettlePhase.selector);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    /*//////////////////////////////////////////////////////////////
                        PLACE BID
    //////////////////////////////////////////////////////////////*/

    function test_PlaceBid_WhenSingle() public setupBasicAuction {  
        bytes32 commitment = _genSealedBid(1 ether, salt1);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
        
        (bytes32 commitmentStored, uint96 bidderBalance, ) = auctions.bidsForAuction(address(drop), address(bidder1));

        assertEq(address(auctions).balance, 1 ether);
        assertEq(bidderBalance, 1 ether);
        assertEq(commitmentStored, commitment);
    }

    function test_PlaceBid_WhenMultiple() public setupBasicAuction {        
        bytes32 commitment1 = _genSealedBid(1 ether, salt1);
        bytes32 commitment2 = _genSealedBid(1 ether, salt2);
        bytes32 commitment3 = _genSealedBid(1 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 3 ether}(address(drop), commitment3);

        (bytes32 commitmentStored1, uint96 bidderBalance1, ) = auctions.bidsForAuction(address(drop), address(bidder1));
        (bytes32 commitmentStored2, uint96 bidderBalance2, ) = auctions.bidsForAuction(address(drop), address(bidder2));
        (bytes32 commitmentStored3, uint96 bidderBalance3, ) = auctions.bidsForAuction(address(drop), address(bidder3));

        assertEq(address(auctions).balance, 6 ether);
        assertEq(bidderBalance1, 1 ether);
        assertEq(bidderBalance2, 2 ether);
        assertEq(bidderBalance3, 3 ether);
        assertEq(commitmentStored1, commitment1);
        assertEq(commitmentStored2, commitment2);
        assertEq(commitmentStored3, commitment3);
    }

    function testEvent_PlaceBid_WhenSingle() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        vm.expectEmit(true, true, true, true);
        emit BidPlaced(address(drop), address(bidder1), auction);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testEvent_PlaceBid_WhenMultiple() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        bytes32 commitment1 = _genSealedBid(1 ether, salt1);
        bytes32 commitment2 = _genSealedBid(1 ether, salt2);
        bytes32 commitment3 = _genSealedBid(1 ether, salt3);

        vm.expectEmit(true, true, true, true);
        emit BidPlaced(address(drop), address(bidder1), auction);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);

        auction.totalBalance = 3 ether; // 2 ether more from bidder 2

        vm.expectEmit(true, true, true, true);
        emit BidPlaced(address(drop), address(bidder2), auction);

        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), commitment2);

        auction.totalBalance = 6 ether; // 3 ether more from bidder 3

        vm.expectEmit(true, true, true, true);
        emit BidPlaced(address(drop), address(bidder3), auction);

        vm.prank(address(bidder3));
        auctions.placeBid{value: 3 ether}(address(drop), commitment3);
    }

    function testRevert_PlaceBid_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days); // reveal phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_BidsOnlyAllowedDuringBidPhase.selector);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInSettlePhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days); // settle phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_BidsOnlyAllowedDuringBidPhase.selector);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInCleanupPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_BidsOnlyAllowedDuringBidPhase.selector);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenBidderAlreadyPlacedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.expectRevert(IVariableSupplyAuction.Bidder_AlreadyPlacedBidInAuction.selector);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenNoEtherIncluded() public setupBasicAuction {
        vm.expectRevert(IVariableSupplyAuction.Bidder_BidsMustIncludeEther.selector);

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid(address(drop), commitment);
    }

    // TODO revisit, may become relevant if we move role granting for
    // edition sizing / minting into an ERC721DropTransferHelper

    // function testRevert_PlaceBid_WhenSellerDidNotApproveModule() public setupBasicAuction {
    //     seller.setApprovalForModule(address(auctions), false);

    //     vm.expectRevert("module has not been approved by user");

    //     bytes32 commitment = _genSealedBid(1 ether, salt1);
    //     vm.prank(address(bidder1));
    //     auctions.placeBid{value: 1 ether}(address(drop), commitment);
    // }

    /*//////////////////////////////////////////////////////////////
                        REVEAL BID
    //////////////////////////////////////////////////////////////*/

    function test_RevealBid_WhenSingle() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);

        (,, uint256 bidAmount) = auctions.bidsForAuction(address(drop), address(bidder1));
        
        assertEq(bidAmount, 1 ether);
    }

    function test_RevealBid_WhenMultiple() public setupBasicAuction {
        bytes32 commitment1 = _genSealedBid(1 ether, salt1);
        bytes32 commitment2 = _genSealedBid(2 ether, salt2);
        bytes32 commitment3 = _genSealedBid(3 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 3 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 5 ether}(address(drop), commitment3);        

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 3 ether, salt3);

        (,, uint256 bidAmount1) = auctions.bidsForAuction(address(drop), address(bidder1));
        (,, uint256 bidAmount2) = auctions.bidsForAuction(address(drop), address(bidder2));
        (,, uint256 bidAmount3) = auctions.bidsForAuction(address(drop), address(bidder3));

        assertEq(bidAmount1, 1 ether);
        assertEq(bidAmount2, 2 ether);
        assertEq(bidAmount3, 3 ether);
    }

    function testEvent_RevealBid_WhenSingle() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days);

        vm.expectEmit(true, true, true, true);
        emit BidRevealed(address(drop), address(bidder1), 1 ether,  auction);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
    }

    function testEvent_RevealBid_WhenMultiple() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 9 ether,
            settledPricePoint: 0,
            settledEditionSize: 0,
            settledRevenue: 0
        });

        bytes32 commitment1 = _genSealedBid(1 ether, salt1);
        bytes32 commitment2 = _genSealedBid(2 ether, salt2);
        bytes32 commitment3 = _genSealedBid(3 ether, salt3);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 3 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 5 ether}(address(drop), commitment3);        

        vm.warp(TIME0 + 3 days);

        // We can assert all events without changing Auction struct, bc stored auction does not change
        vm.expectEmit(true, true, true, true);
        emit BidRevealed(address(drop), address(bidder1), 1 ether,  auction);
        vm.expectEmit(true, true, true, true);
        emit BidRevealed(address(drop), address(bidder2), 2 ether,  auction);
        vm.expectEmit(true, true, true, true);
        emit BidRevealed(address(drop), address(bidder3), 3 ether,  auction);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 3 ether, salt3);
    }

    function testRevert_RevealBid_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    function testRevert_RevealBid_WhenAuctionInBidPhase() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealsOnlyAllowedDuringRevealPhase.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    function testRevert_RevealBid_WhenAuctionInSettlePhase() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days + 2 days); // settle phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealsOnlyAllowedDuringRevealPhase.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    function testRevert_RevealBid_WhenAuctionInCleanupPhase() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealsOnlyAllowedDuringRevealPhase.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    function testRevert_RevealBid_WhenNoCommittedBid() public setupBasicAuction {
        vm.warp(TIME0 + 3 days);

        vm.expectRevert(IVariableSupplyAuction.Bidder_NoPlacedBidByAddressInThisAuction.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1.1 ether, salt1);
    }

    // TODO should we allow "topping up" the bidder's balance to support their bid?
    // likely, no — could introduce bad incentives
    function testRevert_RevealBid_WhenRevealedBidGreaterThanSentEther() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1.1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealedBidCannotBeGreaterThanEtherSentWithSealedBid.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1.1 ether, salt1);
    }

    function testRevert_RevealBid_WhenRevealedAmountDoesNotMatchSealedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment); 

        vm.warp(TIME0 + 3 days);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealedBidDoesNotMatchSealedBid.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 0.9 ether, salt1); // wrong amount
    }

    function testRevert_RevealBid_WhenRevealedSaltDoesNotMatchSealedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RevealedBidDoesNotMatchSealedBid.selector);

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt2); // wrong salt
    }

    /*//////////////////////////////////////////////////////////////
                        FAILURE TO REVEAL BID
    //////////////////////////////////////////////////////////////*/

    // TODO bidder failure to reveal sad paths

    /*//////////////////////////////////////////////////////////////
                        SETTLE AUCTION
    //////////////////////////////////////////////////////////////*/

    function test_CalculateSettleOutcomes() public setupBasicAuction throughRevealPhaseComplex {
        (uint96[] memory pricePoints, uint16[] memory editionSizes, uint96[] memory revenues) = 
            auctions.calculateSettleOutcomes(address(drop));

        assertEq(editionSizes.length, pricePoints.length);
        assertEq(revenues.length, pricePoints.length);

        // for (uint256 i = 0; i < pricePoints.length; i++) {
        //     emit log_string("Outcome -------------");
        //     emit log_named_uint("Price point", pricePoints[i] / 1 ether);
        //     emit log_named_uint("Edition size", editionSizes[i]);
        //     emit log_named_uint("Revenue", revenues[i] / 1 ether);
        // }

        /*

        Expected output:
        
        [Price Point]       [Edition Size]      [Revenue]
        [1]                 [14]                [14]
        [2]                 [4]                 [0]
        [6]                 [3]                 [18]
        [11]                [1]                 [11]

        Note that revenue is set to 0 at price point 2 ether
        because 8 ether would not meet minimum viable revenue
        (and therefore this won't be a viable settle outcome)

         */

         assertEq(pricePoints[0], 1 ether);
         assertEq(editionSizes[0], 14);
         assertEq(revenues[0], 14 ether);

         assertEq(pricePoints[1], 6 ether);
         assertEq(editionSizes[1], 3);
         assertEq(revenues[1], 18 ether);

         assertEq(pricePoints[2], 11 ether);
         assertEq(editionSizes[2], 1);
         assertEq(revenues[2], 11 ether);

         assertEq(pricePoints[3], 2 ether);
         assertEq(editionSizes[3], 4);
         assertEq(revenues[3], 0);
    }

    // 1_794_872-1_691_644 = 103_228 more than once
    // 1_703_719-1_691_757 = 11_962 more than once (with optimization)

    function testGas_AndIdempotent_CalculateSettleOutcomes_WhenCalledTwice() public setupBasicAuction throughRevealPhaseComplex {
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
    }

    // 1_899_651-1_794_851 = 104_800 more than twice
    // 1_717_252-1_703_719 = 13_533 more than twice (with optimization)

    function testGas_AndIdempotent_CalculateSettleOutcomes_WhenCalledThrice() public setupBasicAuction throughRevealPhaseComplex {
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
    }

    // 1_730_788-1_717_253 = 13_535 more than thrice (with optimization)

    function testGas_AndIdempotent_CalculateSettleOutcomes_WhenCalledFrice() public setupBasicAuction throughRevealPhaseComplex {
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
        auctions.calculateSettleOutcomes(address(drop));
    }

    function testRevert_CalculateSettleOutcomes_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));
    }

    function testRevert_CalculateSettleOutcomes_WhenAuctionInBidPhase() public setupBasicAuction {
        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));
    }

    function testRevert_CalculateSettleOutcomes_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days); // reveal phase
        
        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));
    }

    function testRevert_CalculateSettleOutcomes_WhenAuctionInCleanupPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));
    }

    function testRevert_CalculateSettleOutcomes_WhenAuctionHasZeroRevealedBids() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days);        

        vm.expectRevert(IVariableSupplyAuction.Seller_CannotSettleWithNoRevealedBids.selector);

        vm.prank(address(seller));
        auctions.calculateSettleOutcomes(address(drop));
    }

    /*

    Scenario for the following settleAuction tests

        Given The following sealed bids are placed
            | account  | bid amount | sent value |
            | Bidder1  | 1 ETH      | 1 ETH      |
            | Bidder2  | 1 ETH      | 9 ETH      |
            | Bidder3  | 1 ETH      | 8 ETH      |
            | Bidder4  | 1 ETH      | 7 ETH      |
            | Bidder5  | 1 ETH      | 6 ETH      |
            | Bidder6  | 1 ETH      | 5 ETH      |
            | Bidder7  | 1 ETH      | 4 ETH      |
            | Bidder8  | 1 ETH      | 3 ETH      |
            | Bidder9  | 1 ETH      | 2 ETH      |
            | Bidder10 | 1 ETH      | 10 ETH     |
            | Bidder11 | 6 ETH      | 6 ETH      |
            | Bidder12 | 6 ETH      | 9 ETH      |
            | Bidder13 | 11 ETH     | 12 ETH     |
            | Bidder14 | 2 ETH      | 2 ETH      |
        When The seller settles the auction
        Then The seller can choose one of the following edition sizes and revenue amounts
            | edition size | revenue generated |
            | 13           | 13 ether          |
            | 5            | 0 ether           |
            | 3            | 18 ether          |
            | 1            | 11 ether          |

    Note settleAuction tests use throughRevealPhaseComplex modifier for further test setup

    */

    function test_SettleAuction_Preconditions() public setupBasicAuction throughRevealPhaseComplex {        
        // Precondition checks

        // all bidders have 0 NFTs
        assertEq(drop.balanceOf(address(bidder1)), 0);
        assertEq(drop.balanceOf(address(bidder2)), 0);
        assertEq(drop.balanceOf(address(bidder3)), 0);
        assertEq(drop.balanceOf(address(bidder4)), 0);
        assertEq(drop.balanceOf(address(bidder5)), 0);
        assertEq(drop.balanceOf(address(bidder6)), 0);
        assertEq(drop.balanceOf(address(bidder7)), 0);
        assertEq(drop.balanceOf(address(bidder8)), 0);
        assertEq(drop.balanceOf(address(bidder9)), 0);
        assertEq(drop.balanceOf(address(bidder10)), 0);
        assertEq(drop.balanceOf(address(bidder11)), 0);
        assertEq(drop.balanceOf(address(bidder12)), 0);
        assertEq(drop.balanceOf(address(bidder13)), 0);
        assertEq(drop.balanceOf(address(bidder14)), 0);

        // seller funds recipient has 100 ether
        assertEq(address(sellerFundsRecipient).balance, 100 ether);

        // auction total balance still full amount of sent ether
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            ,
            ,
        ) = auctions.auctionForDrop(address(drop));
        assertEq(totalBalance, 84 ether);

        // bidder auction balances each still full amount of sent ether
        (, uint96 bidderBalance1, ) = auctions.bidsForAuction(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForAuction(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForAuction(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForAuction(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForAuction(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForAuction(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForAuction(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForAuction(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForAuction(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForAuction(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForAuction(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForAuction(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForAuction(address(drop), address(bidder13));
        (, uint96 bidderBalance14, ) = auctions.bidsForAuction(address(drop), address(bidder14));
        assertEq(bidderBalance1, 1 ether);
        assertEq(bidderBalance2, 9 ether);
        assertEq(bidderBalance3, 8 ether);
        assertEq(bidderBalance4, 7 ether);
        assertEq(bidderBalance5, 6 ether);
        assertEq(bidderBalance6, 5 ether);
        assertEq(bidderBalance7, 4 ether);
        assertEq(bidderBalance8, 3 ether);
        assertEq(bidderBalance9, 2 ether);
        assertEq(bidderBalance10, 10 ether);
        assertEq(bidderBalance11, 6 ether);
        assertEq(bidderBalance12, 9 ether);
        assertEq(bidderBalance13, 12 ether);
        assertEq(bidderBalance14, 2 ether);
    }

    function test_SettleAuction_WhenSettlingAtLowPriceHighSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(84 ether, 1 ether, 14);        

        // When -- seller settles auction at price point of 1 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        // Then assert --
        // 1) all bidders have 1 NFT
        // 2) seller funds recipient has 114 ether
        // 3) auction total balance is sent ether less settled revenue of 14 ether
        // 4) auction settled revenue, price point, and edition size are correct
        // 5) bidder auction balances (available to withdraw) are their amount of
        // sent ether less the settled price point of 1 ether

        assertEq(drop.balanceOf(address(bidder1)), 1);
        assertEq(drop.balanceOf(address(bidder2)), 1);
        assertEq(drop.balanceOf(address(bidder3)), 1);
        assertEq(drop.balanceOf(address(bidder4)), 1);
        assertEq(drop.balanceOf(address(bidder5)), 1);
        assertEq(drop.balanceOf(address(bidder6)), 1);
        assertEq(drop.balanceOf(address(bidder7)), 1);
        assertEq(drop.balanceOf(address(bidder8)), 1);
        assertEq(drop.balanceOf(address(bidder9)), 1);
        assertEq(drop.balanceOf(address(bidder10)), 1);
        assertEq(drop.balanceOf(address(bidder11)), 1);
        assertEq(drop.balanceOf(address(bidder12)), 1);
        assertEq(drop.balanceOf(address(bidder13)), 1);
        assertEq(drop.balanceOf(address(bidder14)), 1);

        assertEq(address(sellerFundsRecipient).balance, 114 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            uint96 settledPricePoint,
            uint16 settledEditionSize,
            uint96 settledRevenue
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 84 ether - 14 ether);

        assertEq(settledPricePoint, 1 ether);
        assertEq(settledEditionSize, 14);
        assertEq(settledRevenue, 14 ether);

        (, uint96 bidderBalance1, ) = auctions.bidsForAuction(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForAuction(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForAuction(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForAuction(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForAuction(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForAuction(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForAuction(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForAuction(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForAuction(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForAuction(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForAuction(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForAuction(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForAuction(address(drop), address(bidder13));
        (, uint96 bidderBalance14, ) = auctions.bidsForAuction(address(drop), address(bidder14));
        assertEq(bidderBalance1, 0 ether);
        assertEq(bidderBalance2, 8 ether);
        assertEq(bidderBalance3, 7 ether);
        assertEq(bidderBalance4, 6 ether);
        assertEq(bidderBalance5, 5 ether);
        assertEq(bidderBalance6, 4 ether);
        assertEq(bidderBalance7, 3 ether);
        assertEq(bidderBalance8, 2 ether);
        assertEq(bidderBalance9, 1 ether);
        assertEq(bidderBalance10, 9 ether);
        assertEq(bidderBalance11, 5 ether);
        assertEq(bidderBalance12, 8 ether);
        assertEq(bidderBalance13, 11 ether);
        assertEq(bidderBalance14, 1 ether);
    }

    function test_SettleAuction_WhenSettlingAtMidPriceMidSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(84 ether, 6 ether, 3);        

         // When -- seller settles auction at price point of 6 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 6 ether);

        // Then assert --
        // 1) bidders 11–13 has 1 NFT
        // 2) seller funds recipient has 118 ether
        // 3) auction total balance is sent ether less settled revenue of 18 ether
        // 4) auction settled revenue, price point, and edition size are correct
        // 5) bidders 11–13 balance is their sent ether less settled price point of 6 ether
        // 6) bidders 1–10 and 14 balances (available to withdraw) are their full sent ether

        assertEq(drop.balanceOf(address(bidder1)), 0);
        assertEq(drop.balanceOf(address(bidder2)), 0);
        assertEq(drop.balanceOf(address(bidder3)), 0);
        assertEq(drop.balanceOf(address(bidder4)), 0);
        assertEq(drop.balanceOf(address(bidder5)), 0);
        assertEq(drop.balanceOf(address(bidder6)), 0);
        assertEq(drop.balanceOf(address(bidder7)), 0);
        assertEq(drop.balanceOf(address(bidder8)), 0);
        assertEq(drop.balanceOf(address(bidder9)), 0);
        assertEq(drop.balanceOf(address(bidder10)), 0);
        assertEq(drop.balanceOf(address(bidder11)), 1);
        assertEq(drop.balanceOf(address(bidder12)), 1);
        assertEq(drop.balanceOf(address(bidder13)), 1);
        assertEq(drop.balanceOf(address(bidder14)), 0);

        assertEq(address(sellerFundsRecipient).balance, 118 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            uint96 settledPricePoint,
            uint16 settledEditionSize,
            uint96 settledRevenue
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 84 ether - 18 ether);

        assertEq(settledPricePoint, 6 ether);
        assertEq(settledEditionSize, 3);
        assertEq(settledRevenue, 18 ether);

        (, uint96 bidderBalance1, ) = auctions.bidsForAuction(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForAuction(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForAuction(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForAuction(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForAuction(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForAuction(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForAuction(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForAuction(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForAuction(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForAuction(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForAuction(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForAuction(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForAuction(address(drop), address(bidder13));
        (, uint96 bidderBalance14, ) = auctions.bidsForAuction(address(drop), address(bidder14));
        assertEq(bidderBalance1, 1 ether);
        assertEq(bidderBalance2, 9 ether);
        assertEq(bidderBalance3, 8 ether);
        assertEq(bidderBalance4, 7 ether);
        assertEq(bidderBalance5, 6 ether);
        assertEq(bidderBalance6, 5 ether);
        assertEq(bidderBalance7, 4 ether);
        assertEq(bidderBalance8, 3 ether);
        assertEq(bidderBalance9, 2 ether);
        assertEq(bidderBalance10, 10 ether);
        assertEq(bidderBalance11, 0 ether);
        assertEq(bidderBalance12, 3 ether);
        assertEq(bidderBalance13, 6 ether);
        assertEq(bidderBalance14, 2 ether);
    }

    function test_SettleAuction_WhenSettlingAtHighPriceLowSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(84 ether, 11 ether, 1);        

        // When -- seller settles auction at price point of 11 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 11 ether);

        // Then assert --
        // 1) bidder 13 has 1 NFT
        // 2) seller funds recipient has 111 ether
        // 3) auction total balance is sent ether less settled revenue of 11 ether
        // 4) auction settled revenue, price point, and edition size are correct
        // 5) bidder 13 auction balance is their sent ether less settled price point of 11 ether
        // 6) bidders 1–12 and 14 balances (available to withdraw) are their full sent ether

        assertEq(drop.balanceOf(address(bidder1)), 0);
        assertEq(drop.balanceOf(address(bidder2)), 0);
        assertEq(drop.balanceOf(address(bidder3)), 0);
        assertEq(drop.balanceOf(address(bidder4)), 0);
        assertEq(drop.balanceOf(address(bidder5)), 0);
        assertEq(drop.balanceOf(address(bidder6)), 0);
        assertEq(drop.balanceOf(address(bidder7)), 0);
        assertEq(drop.balanceOf(address(bidder8)), 0);
        assertEq(drop.balanceOf(address(bidder9)), 0);
        assertEq(drop.balanceOf(address(bidder10)), 0);
        assertEq(drop.balanceOf(address(bidder11)), 0);
        assertEq(drop.balanceOf(address(bidder12)), 0);
        assertEq(drop.balanceOf(address(bidder13)), 1);
        assertEq(drop.balanceOf(address(bidder14)), 0);

        assertEq(address(sellerFundsRecipient).balance, 111 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            uint96 settledPricePoint,
            uint16 settledEditionSize,
            uint96 settledRevenue
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 84 ether - 11 ether);

        assertEq(settledPricePoint, 11 ether);
        assertEq(settledEditionSize, 1);
        assertEq(settledRevenue, 11 ether);

        (, uint96 bidderBalance1, ) = auctions.bidsForAuction(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForAuction(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForAuction(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForAuction(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForAuction(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForAuction(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForAuction(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForAuction(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForAuction(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForAuction(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForAuction(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForAuction(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForAuction(address(drop), address(bidder13));
        (, uint96 bidderBalance14, ) = auctions.bidsForAuction(address(drop), address(bidder14));
        assertEq(bidderBalance1, 1 ether);
        assertEq(bidderBalance2, 9 ether);
        assertEq(bidderBalance3, 8 ether);
        assertEq(bidderBalance4, 7 ether);
        assertEq(bidderBalance5, 6 ether);
        assertEq(bidderBalance6, 5 ether);
        assertEq(bidderBalance7, 4 ether);
        assertEq(bidderBalance8, 3 ether);
        assertEq(bidderBalance9, 2 ether);
        assertEq(bidderBalance10, 10 ether);
        assertEq(bidderBalance11, 6 ether);
        assertEq(bidderBalance12, 9 ether);
        assertEq(bidderBalance13, 1 ether);
        assertEq(bidderBalance14, 2 ether);
    }

    // TODO consider different ordering of checks

    // function testRevert_SettleAuction_WhenAuctionDoesNotExist() public {
    //     vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

    //     vm.prank(address(seller));
    //     auctions.settleAuction(address(drop), 1 ether);
    // }

    function testRevert_SettleAuction_WhenNotSeller() public setupBasicAuction throughRevealPhaseComplex {
        vm.expectRevert(IVariableSupplyAuction.Access_OnlySeller.selector);

        auctions.settleAuction(address(drop), 1 ether);
    }

    function testRevert_SettleAuction_WhenAuctionInBidPhase() public setupBasicAuction {
        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);
    }

    function testRevert_SettleAuction_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days); // reveal phase
        
        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);
    }

    function testRevert_SettleAuction_WhenAuctionInCleanupPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectRevert(IVariableSupplyAuction.Seller_SettleAuctionOnlyAllowedDuringSettlePhase.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);
    }

    function testRevert_SettleAuction_WhenAuctionHasZeroRevealedBids() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days);

        vm.expectRevert(IVariableSupplyAuction.Seller_CannotSettleWithNoRevealedBids.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);
    }

    function testRevert_SettleAuction_WhenSettlingAtPricePointThatDoesNotMeetMinimumViableRevenue() public setupBasicAuction throughRevealPhaseComplex {
        vm.expectRevert(IVariableSupplyAuction.Seller_PricePointDoesNotMeetMinimumViableRevenue.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether); // does not meet minimum viable revenue
    }

    function testRevert_SettleAuction_WhenSettlingAtInvalidPricePoint() public setupBasicAuction throughRevealPhaseComplex {
        vm.expectRevert(IVariableSupplyAuction.Seller_PricePointDoesNotMeetMinimumViableRevenue.selector);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 3 ether); // non-existent settle price point
    }

    /*//////////////////////////////////////////////////////////////
                        FAILURE TO SETTLE AUCTION
    //////////////////////////////////////////////////////////////*/

    // TODO seller failure to settle sad paths

    /*//////////////////////////////////////////////////////////////
                        CLAIM REFUND
    //////////////////////////////////////////////////////////////*/

    function test_CheckAvailableRefund() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));
        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(2 ether, salt2));
        vm.prank(address(bidder3));
        auctions.placeBid{value: 3 ether}(address(drop), _genSealedBid(2 ether, salt3));

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 2 ether, salt3);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.prank(address(bidder1));
        assertEq(auctions.checkAvailableRefund(address(drop)), 2 ether); // = full amount sent, not winning bid

        vm.prank(address(bidder2));
        assertEq(auctions.checkAvailableRefund(address(drop)), 0 ether); // = 2 ether sent - 2 ether winning bid

        vm.prank(address(bidder3));
        assertEq(auctions.checkAvailableRefund(address(drop)), 1 ether); // = 3 ether sent - 2 ether winning bid
    }

    function testRevert_CheckAvailableRefund_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        vm.prank(address(bidder1));
        auctions.checkAvailableRefund(address(drop));
    }

    function testRevert_CheckAvailableRefund_WhenAuctionInBidPhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.checkAvailableRefund(address(drop));
    }

    function testRevert_CheckAvailableRefund_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.warp(TIME0 + 3 days); // reveal phase

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.checkAvailableRefund(address(drop));
    }

    function testRevert_CheckAvailableRefund_WhenAuctionInSettlePhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);

        vm.warp(TIME0 + 3 days + 2 days); // settle phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.checkAvailableRefund(address(drop));
    }

    function test_ClaimRefund_WhenWinner() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        // Precondition checks        
        assertEq(address(bidder1).balance, 98 ether);
        (, uint96 bidderBalance, ) = auctions.bidsForAuction(address(drop), address(bidder1));        
        assertEq(bidderBalance, 1 ether);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        assertEq(address(bidder1).balance, 99 ether);
        (, bidderBalance, ) = auctions.bidsForAuction(address(drop), address(bidder1));        
        assertEq(bidderBalance, 0 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            ,
            ,
            
        ) = auctions.auctionForDrop(address(drop));
        assertEq(totalBalance, 0); // no balance remaining for auction
    }

    function test_ClaimRefund_WhenNotWinner() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 
        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(2 ether, salt2)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);  
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 2 ether, salt2);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 2 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        // Precondition checks        
        assertEq(address(bidder1).balance, 98 ether);
        (, uint96 bidderBalance, ) = auctions.bidsForAuction(address(drop), address(bidder1));        
        assertEq(bidderBalance, 2 ether);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        assertEq(address(bidder1).balance, 100 ether); // claim their full amount of sent ether
        (, bidderBalance, ) = auctions.bidsForAuction(address(drop), address(bidder1));        
        assertEq(bidderBalance, 0 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            ,
            ,
            
        ) = auctions.auctionForDrop(address(drop));
        assertEq(totalBalance, 0); // no balance remaining for auction
    }

    function testEvent_ClaimRefund() public setupBasicAuctionWithLowMinimumViableRevenue {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 0,
            settledPricePoint: 1 ether,
            settledEditionSize: uint16(1),
            settledRevenue: 1 ether
        });

        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectEmit(true, true, true, true);
        emit RefundClaimed(address(drop), address(bidder1), 1 ether, auction);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenAuctionDoesNotExist() public {
        vm.expectRevert(IVariableSupplyAuction.Auction_AuctionDoesNotExist.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenAuctionInBidPhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.warp(TIME0 + 3 days); // reveal phase

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenAuctionInSettlePhase() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1));

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);

        vm.warp(TIME0 + 3 days + 2 days); // settle phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_RefundsOnlyAllowedDuringCleanupPhase.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenNoBidPlaced() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.warp(TIME0 + 3 days + 2 days + 1 days);

        vm.expectRevert(IVariableSupplyAuction.Bidder_NoRefundAvailableForAuction.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenNoBidRevealed() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 
        vm.prank(address(bidder2));
        auctions.placeBid{value: 1 ether}(address(drop), _genSealedBid(1 ether, salt2)); 

        vm.warp(TIME0 + 3 days);

        // bidder1 never revealed =(
        // Note bidder2 must reveal in this test, otherwise seller can't settle bc no revealed bids
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 1 ether, salt2);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.expectRevert(IVariableSupplyAuction.Bidder_NoRefundAvailableForAuction.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenAlreadyClaimed() public setupBasicAuctionWithLowMinimumViableRevenue {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.warp(TIME0 + 3 days + 2 days + 1 days); // cleanup phase

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        vm.expectRevert(IVariableSupplyAuction.Bidder_NoRefundAvailableForAuction.selector);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    /*//////////////////////////////////////////////////////////////
                        TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    /*

    Checks for each action

    Create Auction
    - check there is no live auction for the drop contract already
    - check the funds recipient is not zero address

    Cancel Auction
    - check the auction exists
    - check the caller is the seller
    - check there are no bids placed yet
    - OR, if in settle phase:
    -     check that seller has first considered the settle price points
    -     check that no settle price points meet minimum viable revenue

    Place Bid
    - check the auction exists
    - check the auction is in bid phase
    - check the bidder has not placed a bid yet
    - check the bid is valid

    Reveal Bid
    - check the auction exists
    - check the auction is in reveal phase
    - check the bidder placed a bid in the auction
    - check the revealed amount is not greater than sent ether
    - check the revealed bid matches the sealed bid

    Calculate Settle Outcomes
    - check the auction exists
    - check the auction is in settle phase
    - check the auction has at least 1 revealed bid

    Settle Auction
    - (includes checks from calling calculate settle outcomes, either in this call or previously)
    - check that price point is a valid settle outcome (exists and meets minimum viable revenue)

    Check Available Refund
    - check the auction exists
    - check the auction is in cleanup phase

    Claim Refund
    - check the auction exists
    - check the auction is in cleanup phase
    - check the bidder has a leftover balance

    */

    // TODO parameterize modifier pattern to enable easier fuzzing

    modifier setupBasicAuction() {
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 10 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        _;
    }
    modifier setupBasicAuctionWithLowMinimumViableRevenue() {
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        _;
    }

    modifier throughRevealPhaseComplex() {
        // 10 bids at 1 ether
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), _genSealedBid(1 ether, salt1));   
        vm.prank(address(bidder2));
        auctions.placeBid{value: 9 ether}(address(drop), _genSealedBid(1 ether, salt2));   
        vm.prank(address(bidder3));
        auctions.placeBid{value: 8 ether}(address(drop), _genSealedBid(1 ether, salt3));   
        vm.prank(address(bidder4));
        auctions.placeBid{value: 7 ether}(address(drop), _genSealedBid(1 ether, salt4));   
        vm.prank(address(bidder5));
        auctions.placeBid{value: 6 ether}(address(drop), _genSealedBid(1 ether, salt5));   
        vm.prank(address(bidder6));
        auctions.placeBid{value: 5 ether}(address(drop), _genSealedBid(1 ether, salt6));   
        vm.prank(address(bidder7));
        auctions.placeBid{value: 4 ether}(address(drop), _genSealedBid(1 ether, salt7));   
        vm.prank(address(bidder8));
        auctions.placeBid{value: 3 ether}(address(drop), _genSealedBid(1 ether, salt8));   
        vm.prank(address(bidder9));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt9));   
        vm.prank(address(bidder10));
        auctions.placeBid{value: 10 ether}(address(drop), _genSealedBid(1 ether, salt10));   

        // 2 bids at 6 ether
        vm.prank(address(bidder11));
        auctions.placeBid{value: 6 ether}(address(drop), _genSealedBid(6 ether, salt11));   
        vm.prank(address(bidder12));
        auctions.placeBid{value: 9 ether}(address(drop), _genSealedBid(6 ether, salt12));   

        // 10 bids at 1 ether
        vm.prank(address(bidder13));
        auctions.placeBid{value: 12 ether}(address(drop), _genSealedBid(11 ether, salt13));

        // 1 bid at 2 ether
        vm.prank(address(bidder14));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(2 ether, salt14));

        vm.warp(TIME0 + 3 days);
        
        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);
        vm.prank(address(bidder2));
        auctions.revealBid(address(drop), 1 ether, salt2);
        vm.prank(address(bidder3));
        auctions.revealBid(address(drop), 1 ether, salt3);
        vm.prank(address(bidder4));
        auctions.revealBid(address(drop), 1 ether, salt4);
        vm.prank(address(bidder5));
        auctions.revealBid(address(drop), 1 ether, salt5);
        vm.prank(address(bidder6));
        auctions.revealBid(address(drop), 1 ether, salt6);
        vm.prank(address(bidder7));
        auctions.revealBid(address(drop), 1 ether, salt7);
        vm.prank(address(bidder8));
        auctions.revealBid(address(drop), 1 ether, salt8);
        vm.prank(address(bidder9));
        auctions.revealBid(address(drop), 1 ether, salt9);
        vm.prank(address(bidder10));
        auctions.revealBid(address(drop), 1 ether, salt10);
        vm.prank(address(bidder11));
        auctions.revealBid(address(drop), 6 ether, salt11);
        vm.prank(address(bidder12));
        auctions.revealBid(address(drop), 6 ether, salt12);
        vm.prank(address(bidder13));
        auctions.revealBid(address(drop), 11 ether, salt13);
        vm.prank(address(bidder14));
        auctions.revealBid(address(drop), 2 ether, salt14);

        vm.warp(TIME0 + 3 days + 2 days);        

        _;
    }

    function _expectSettledAuctionEvent(uint96 _beforeSettleTotalBalance, uint96 _settledPricePoint, uint16 _settledEditionSize) internal {
        uint96 settledRevenue = _settledPricePoint * _settledEditionSize;
        uint96 totalBalance = _beforeSettleTotalBalance - settledRevenue;

        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 10 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: totalBalance,
            settledPricePoint: _settledPricePoint,
            settledEditionSize: _settledEditionSize,
            settledRevenue: settledRevenue
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(drop), auction);
    }

    // IDEA could genSealedBid be moved onto the hyperstructure module for better bidder usability ?!

    function _genSealedBid(uint256 _amount, string memory _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_amount, bytes(_salt)));
    }

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(address indexed tokenContract, VariableSupplyAuction.Auction auction);
    event AuctionCanceled(address indexed tokenContract, VariableSupplyAuction.Auction auction);
    event BidPlaced(address indexed tokenContract, address indexed bidder, VariableSupplyAuction.Auction auction);    
    event BidRevealed(address indexed tokenContract, address indexed bidder, uint256 indexed bidAmount, VariableSupplyAuction.Auction auction);
    event AuctionSettled(address indexed tokenContract, VariableSupplyAuction.Auction auction);
    event RefundClaimed(address indexed tokenContract, address indexed bidder, uint96 refundAmount, VariableSupplyAuction.Auction auction);
}
