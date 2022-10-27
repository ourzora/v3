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

// TODO x more temporal checks
// TODO x improve settle auction biz logic and storage
// TODO x review

/// @title VariableSupplyAuctionTest
/// @notice Unit Tests for Variable Supply Auctions
contract VariableSupplyAuctionTest is Test {
    //

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    // ERC20TransferHelper internal erc20TransferHelper;
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

    uint32 internal constant TIME0 = 1_666_000_000; // now-ish

    function setUp() public {
        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        // erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
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
                        CREATE AUCTION
    //////////////////////////////////////////////////////////////*/

    function testGas_CreateAuction() public {
        // Note this basic setup is applied to other tests via the setupBasicAuction modifier
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
        assertEq(minimumViableRevenue, 1 ether);
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
            _minimumViableRevenue: 1 ether,
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
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 0,
            settledRevenue: 0,
            settledPricePoint: 0,
            settledEditionSize: 0
        });

        vm.expectEmit(false, false, false, false);
        emit AuctionCreated(address(drop), auction);

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
    }

    function testRevert_CreateAuction_WhenDropHasLiveAuction() public setupBasicAuction {
        vm.expectRevert("ONLY_ONE_LIVE_AUCTION_PER_DROP");

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
    }

    function testRevert_CreateAuction_WhenDidNotSpecifySellerFundsRecipient() public {
        vm.expectRevert("INVALID_FUNDS_RECIPIENT");

        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumViableRevenue: 1 ether,
            _sellerFundsRecipient: address(0),
            _startTime: TIME0,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

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

    function testEvent_CancelAuction() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 0,
            settledRevenue: 0,
            settledPricePoint: 0,
            settledEditionSize: 0
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionCanceled(address(drop), auction);

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenNotSeller() public setupBasicAuction {
        vm.expectRevert("ONLY_SELLER");

        vm.prank(address(bidder1));
        auctions.cancelAuction(address(drop));
    }

    function testRevert_CancelAuction_WhenBidAlreadyPlaced() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.expectRevert("CANNOT_CANCEL_AUCTION_WITH_BIDS");

        vm.prank(address(seller));
        auctions.cancelAuction(address(drop));
    }

    // TODO x update biz logic to allow one other case -- cancelling auctions
    // in settle phase that did not meet minimum viable revenue goal

    /*//////////////////////////////////////////////////////////////
                        PLACE BID
    //////////////////////////////////////////////////////////////*/

    // TODO x add more assertions around new storage variables

    function test_PlaceBid_WhenSingle() public setupBasicAuction {  
        bytes32 commitment = _genSealedBid(1 ether, salt1);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
        
        (bytes32 commitmentStored, uint96 bidderBalance, ) = auctions.bidsForDrop(address(drop), address(bidder1));

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

        (bytes32 commitmentStored1, uint96 bidderBalance1, ) = auctions.bidsForDrop(address(drop), address(bidder1));
        (bytes32 commitmentStored2, uint96 bidderBalance2, ) = auctions.bidsForDrop(address(drop), address(bidder2));
        (bytes32 commitmentStored3, uint96 bidderBalance3, ) = auctions.bidsForDrop(address(drop), address(bidder3));

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
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledRevenue: uint96(0),
            settledPricePoint: uint96(0),
            settledEditionSize: uint16(0)
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
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledRevenue: uint96(0),
            settledPricePoint: uint96(0),
            settledEditionSize: uint16(0)
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
        vm.expectRevert("AUCTION_DOES_NOT_EXIST");

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days); // reveal phase

        vm.expectRevert("BIDS_ONLY_ALLOWED_DURING_BID_PHASE");

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInSettlePhase() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days); // settle phase

        vm.expectRevert("BIDS_ONLY_ALLOWED_DURING_BID_PHASE");

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    // TODO x once settleAuction is written
    // function testRevert_PlaceBid_WhenAuctionIsCompleted() public setupBasicAuction {
        
    // }

    // TODO x once cancelAuction is written
    // function testRevert_PlaceBid_WhenAuctionIsCancelled() public setupBasicAuction {
        
    // }

    function testRevert_PlaceBid_WhenBidderAlreadyPlacedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.expectRevert("ALREADY_PLACED_BID_IN_AUCTION");

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenNoEtherIncluded() public setupBasicAuction {
        vm.expectRevert("VALID_BIDS_MUST_INCLUDE_ETHER");

        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid(address(drop), commitment);
    }

    // TODO revisit -– may become relevant if we move minter role granting into an ERC721DropTransferHelper
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

        (,, uint256 bidAmount) = auctions.bidsForDrop(address(drop), address(bidder1));
        
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

        (,, uint256 bidAmount1) = auctions.bidsForDrop(address(drop), address(bidder1));
        (,, uint256 bidAmount2) = auctions.bidsForDrop(address(drop), address(bidder2));
        (,, uint256 bidAmount3) = auctions.bidsForDrop(address(drop), address(bidder3));

        assertEq(bidAmount1, 1 ether);
        assertEq(bidAmount2, 2 ether);
        assertEq(bidAmount3, 3 ether);
    }

    function testEvent_RevealBid_WhenSingle() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledRevenue: uint96(0),
            settledPricePoint: uint96(0),
            settledEditionSize: uint16(0)
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
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 9 ether,
            settledRevenue: uint96(0),
            settledPricePoint: uint96(0),
            settledEditionSize: uint16(0)
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

        // We can assert all events at once, bc stored auction does not change
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

    function testRevert_RevealBid_WhenAuctionInBidPhase() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.expectRevert("REVEALS_ONLY_ALLOWED_DURING_REVEAL_PHASE");

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    function testRevert_RevealBid_WhenAuctionInSettlePhase() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1.1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days + 2 days);

        vm.expectRevert("REVEALS_ONLY_ALLOWED_DURING_REVEAL_PHASE");

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1 ether, salt1);
    }

    // TODO x once settleAuction is written
    // function testRevert_RevealBid_WhenAuctionIsCompleted() public setupBasicAuction {
        
    // }

    // TODO x once cancelAuction is written
    // function testRevert_RevealBid_WhenAuctionIsCancelled() public setupBasicAuction {
        
    // }

    function testRevert_RevealBid_WhenNoCommittedBid() public setupBasicAuction {
        vm.warp(TIME0 + 3 days);

        vm.expectRevert("NO_PLACED_BID_FOUND_FOR_ADDRESS");

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

        vm.expectRevert("REVEALED_BID_CANNOT_BE_GREATER_THAN_SENT_ETHER");

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 1.1 ether, salt1);
    }

    function testRevert_RevealBid_WhenRevealedAmountDoesNotMatchSealedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment); 

        vm.warp(TIME0 + 3 days);

        vm.expectRevert("REVEALED_BID_DOES_NOT_MATCH_SEALED_BID");

        vm.prank(address(bidder1));
        auctions.revealBid(address (drop), 0.9 ether, salt1); // wrong amount
    }

    function testRevert_RevealBid_WhenRevealedSaltDoesNotMatchSealedBid() public setupBasicAuction {
        bytes32 commitment = _genSealedBid(1 ether, salt1);
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.warp(TIME0 + 3 days);

        vm.expectRevert("REVEALED_BID_DOES_NOT_MATCH_SEALED_BID");

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

    function test_CalculateSettleOptions() public setupBasicAuction throughRevealPhaseComplex {
        (uint96[] memory pricePoints, uint16[] memory editionSizes, uint96[] memory revenues) = 
            auctions.calculateSettleOptions(address(drop));

        assertEq(editionSizes.length, pricePoints.length);
        assertEq(revenues.length, pricePoints.length);

        // for (uint256 i = 0; i < pricePoints.length; i++) {
        //     emit log_string("Option -------------");
        //     emit log_named_uint("Price point", pricePoints[i] / 1 ether);
        //     emit log_named_uint("Edition size", editionSizes[i]);
        //     emit log_named_uint("Revenue", revenues[i] / 1 ether);
        // }

        /*

        Expected output:
        
        [Price Point]       [Edition Size]      [Revenue]
        [1]                 [13]                [13]
        [6]                 [3]                 [18]
        [11]                [1]                 [11]

         */

         assertEq(pricePoints[0], 1 ether);
         assertEq(editionSizes[0], 13);
         assertEq(revenues[0], 13 ether);

         assertEq(pricePoints[1], 6 ether);
         assertEq(editionSizes[1], 3);
         assertEq(revenues[1], 18 ether);

         assertEq(pricePoints[2], 11 ether);
         assertEq(editionSizes[2], 1);
         assertEq(revenues[2], 11 ether);
    }

    /*

    Scenario for the following 3 settleAuction unit tests

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
        When The seller settles the auction
        Then The seller can choose one of the following edition sizes and revenue amounts
            | edition size | revenue generated |
            | 13           | 13 ether          |
            | 3            | 18 ether          |
            | 1            | 11 ether          |

    Note settle auction tests use throughRevealPhaseComplex modifier for further test setup

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
        assertEq(totalBalance, 82 ether);

        // bidder auction balances each still full amount of sent ether
        (, uint96 bidderBalance1, ) = auctions.bidsForDrop(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForDrop(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForDrop(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForDrop(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForDrop(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForDrop(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForDrop(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForDrop(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForDrop(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForDrop(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForDrop(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForDrop(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForDrop(address(drop), address(bidder13));
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
    }

    function test_SettleAuction_WhenSettlingAtLowPriceHighSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(82 ether, 1 ether, 13);        

        // When -- seller settles auction at price point of 1 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        // Then assert --
        // 1) all bidders have 1 NFT
        // 2) seller funds recipient has 113 ether
        // 3) auction total balance is sent ether less settled revenue of 13 ether
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

        assertEq(address(sellerFundsRecipient).balance, 113 ether);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint96 totalBalance,
            uint96 settledRevenue,
            uint96 settledPricePoint,
            uint16 settledEditionSize
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 82 ether - 13 ether);

        assertEq(settledRevenue, 13 ether);
        assertEq(settledPricePoint, 1 ether);
        assertEq(settledEditionSize, 13);

        (, uint96 bidderBalance1, ) = auctions.bidsForDrop(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForDrop(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForDrop(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForDrop(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForDrop(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForDrop(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForDrop(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForDrop(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForDrop(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForDrop(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForDrop(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForDrop(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForDrop(address(drop), address(bidder13));
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
    }

    function test_SettleAuction_WhenSettlingAtMidPriceMidSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(82 ether, 6 ether, 3);        

         // When -- seller settles auction at price point of 6 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 6 ether);

        // Then assert --
        // 1) bidders 11–13 has 1 NFT
        // 2) seller funds recipient has 118 ether
        // 3) auction total balance is sent ether less settled revenue of 18 ether
        // 4) auction settled revenue, price point, and edition size are correct
        // 5) bidders 11–13 balance is their sent ether less settled price point of 6 ether
        // 6) bidders 1–10 balances (available to withdraw) are their full sent ether

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
            uint96 settledRevenue,
            uint96 settledPricePoint,
            uint16 settledEditionSize
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 82 ether - 18 ether);

        assertEq(settledRevenue, 18 ether);
        assertEq(settledPricePoint, 6 ether);
        assertEq(settledEditionSize, 3);

        (, uint96 bidderBalance1, ) = auctions.bidsForDrop(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForDrop(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForDrop(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForDrop(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForDrop(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForDrop(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForDrop(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForDrop(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForDrop(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForDrop(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForDrop(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForDrop(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForDrop(address(drop), address(bidder13));
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
    }

    function test_SettleAuction_WhenSettlingAtHighPriceLowSupply() public setupBasicAuction throughRevealPhaseComplex {
        _expectSettledAuctionEvent(82 ether, 11 ether, 1);        

        // When -- seller settles auction at price point of 11 ether
        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 11 ether);

        // Then assert --
        // 1) bidder 13 has 1 NFT
        // 2) seller funds recipient has 111 ether
        // 3) auction total balance is sent ether less settled revenue of 11 ether
        // 4) auction settled revenue, price point, and edition size are correct
        // 5) bidder 13 auction balance is their sent ether less settled price point of 11 ether
        // 6) bidders 1–12 auction balances (available to withdraw) are their full sent ether

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
            uint96 settledRevenue,
            uint96 settledPricePoint,
            uint16 settledEditionSize
        ) = auctions.auctionForDrop(address(drop));

        assertEq(totalBalance, 82 ether - 11 ether);

        assertEq(settledRevenue, 11 ether);
        assertEq(settledPricePoint, 11 ether);
        assertEq(settledEditionSize, 1);

        (, uint96 bidderBalance1, ) = auctions.bidsForDrop(address(drop), address(bidder1));
        (, uint96 bidderBalance2, ) = auctions.bidsForDrop(address(drop), address(bidder2));
        (, uint96 bidderBalance3, ) = auctions.bidsForDrop(address(drop), address(bidder3));
        (, uint96 bidderBalance4, ) = auctions.bidsForDrop(address(drop), address(bidder4));
        (, uint96 bidderBalance5, ) = auctions.bidsForDrop(address(drop), address(bidder5));
        (, uint96 bidderBalance6, ) = auctions.bidsForDrop(address(drop), address(bidder6));
        (, uint96 bidderBalance7, ) = auctions.bidsForDrop(address(drop), address(bidder7));
        (, uint96 bidderBalance8, ) = auctions.bidsForDrop(address(drop), address(bidder8));
        (, uint96 bidderBalance9, ) = auctions.bidsForDrop(address(drop), address(bidder9));
        (, uint96 bidderBalance10, ) = auctions.bidsForDrop(address(drop), address(bidder10));
        (, uint96 bidderBalance11, ) = auctions.bidsForDrop(address(drop), address(bidder11));
        (, uint96 bidderBalance12, ) = auctions.bidsForDrop(address(drop), address(bidder12));
        (, uint96 bidderBalance13, ) = auctions.bidsForDrop(address(drop), address(bidder13));
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
    }

    /*//////////////////////////////////////////////////////////////
                        FAILURE TO SETTLE AUCTION
    //////////////////////////////////////////////////////////////*/

    // TODO seller failure to settle sad paths

    /*//////////////////////////////////////////////////////////////
                        CLAIM REFUND
    //////////////////////////////////////////////////////////////*/

    function test_CheckAvailableRefund() public setupBasicAuction {
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

        vm.prank(address(bidder1));
        assertEq(auctions.checkAvailableRefund(address(drop)), 2 ether); // = full amount sent, not winning bid

        vm.prank(address(bidder2));
        assertEq(auctions.checkAvailableRefund(address(drop)), 0 ether); // = 2 ether sent - 2 ether winning bid

        vm.prank(address(bidder3));
        assertEq(auctions.checkAvailableRefund(address(drop)), 1 ether); // = 3 ether sent - 2 ether winning bid
    }

    function test_ClaimRefund_WhenWinner() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        // Precondition checks        
        assertEq(address(bidder1).balance, 98 ether);
        (, uint96 bidderBalance, ) = auctions.bidsForDrop(address(drop), address(bidder1));        
        assertEq(bidderBalance, 1 ether);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        assertEq(address(bidder1).balance, 99 ether);
        (, bidderBalance, ) = auctions.bidsForDrop(address(drop), address(bidder1));        
        assertEq(bidderBalance, 0 ether);
    }

    function test_ClaimRefund_WhenNotWinner() public setupBasicAuction {
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

        // Precondition checks        
        assertEq(address(bidder1).balance, 98 ether);
        (, uint96 bidderBalance, ) = auctions.bidsForDrop(address(drop), address(bidder1));        
        assertEq(bidderBalance, 2 ether);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        assertEq(address(bidder1).balance, 100 ether); // claim their full amount of sent ether
        (, bidderBalance, ) = auctions.bidsForDrop(address(drop), address(bidder1));        
        assertEq(bidderBalance, 0 ether);
    }

    function testEvent_ClaimRefund() public setupBasicAuction {
        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: 1 ether,
            settledRevenue: 1 ether,
            settledPricePoint: 1 ether,
            settledEditionSize: uint16(1)
        });

        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.expectEmit(true, true, true, true);
        emit RefundClaimed(address(drop), address(bidder1), 1 ether, auction);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    function testRevert_ClaimRefund_WhenNoBidPlaced() public setupBasicAuction {
        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.expectRevert("NO_REFUND_AVAILABLE");

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    // function testRevert_ClaimRefund_WhenNoBidRevealed() public setupBasicAuction {
    //     // TODO x
    // }

    function testRevert_ClaimRefund_WhenAlreadyClaimed() public setupBasicAuction {
        vm.prank(address(bidder1));
        auctions.placeBid{value: 2 ether}(address(drop), _genSealedBid(1 ether, salt1)); 

        vm.warp(TIME0 + 3 days);

        vm.prank(address(bidder1));
        auctions.revealBid(address(drop), 1 ether, salt1);       

        vm.warp(TIME0 + 3 days + 2 days);

        vm.prank(address(seller));
        auctions.settleAuction(address(drop), 1 ether);

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));

        vm.expectRevert("NO_REFUND_AVAILABLE");

        vm.prank(address(bidder1));
        auctions.claimRefund(address(drop));
    }

    // TODO x add temporal sad paths

    /*//////////////////////////////////////////////////////////////
                        TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    // TODO parameterize modifier pattern to support fuzzing
    modifier setupBasicAuction() {
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

        vm.warp(TIME0 + 3 days + 2 days);        

        _;
    }

    function _expectSettledAuctionEvent(uint96 _beforeSettleTotalBalance, uint96 _settledPricePoint, uint16 _settledEditionSize) internal {
        uint96 settledRevenue = _settledPricePoint * _settledEditionSize;
        uint96 totalBalance = _beforeSettleTotalBalance - settledRevenue;

        VariableSupplyAuction.Auction memory auction = VariableSupplyAuction.Auction({
            seller: address(seller),
            minimumViableRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(TIME0),
            endOfBidPhase: uint32(TIME0 + 3 days),
            endOfRevealPhase: uint32(TIME0 + 3 days + 2 days),
            endOfSettlePhase: uint32(TIME0 + 3 days + 2 days + 1 days),
            totalBalance: totalBalance,
            settledRevenue: settledRevenue,
            settledPricePoint: _settledPricePoint,
            settledEditionSize: _settledEditionSize
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionSettled(address(drop), auction);
    }

    // IDEA could this be moved onto the hyperstructure module for better bidder usability ?!
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
