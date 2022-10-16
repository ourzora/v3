// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {VariableSupplyAuction} from "../../../modules/VariableSupplyAuction/VariableSupplyAuction.sol";
import {ERC721Drop} from "../../../modules/VariableSupplyAuction/temp-ERC721Drop.sol";

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
    // ERC20TransferHelper internal erc20TransferHelper;
    // ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    VariableSupplyAuction internal auctions;
    ERC721Drop internal drop;
    // WETH internal weth;

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

    function setUp() public {
        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        // erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
        // erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

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
        drop.initialize({
            _contractName: "Test Mutant Ninja Turtles",
            _contractSymbol: "TMNT",
            _initialOwner: address(seller),
            _fundsRecipient: payable(sellerFundsRecipient),
            _editionSize: 1,
            _royaltyBPS: 1000
            // _metadataRenderer: dummyRenderer,
            // _metadataRendererInit: "",
            // _salesConfig: IERC721Drop.SalesConfiguration({
            //     publicSaleStart: 0,
            //     publicSaleEnd: 0,
            //     presaleStart: 0,
            //     presaleEnd: 0,
            //     publicSalePrice: 0,
            //     maxSalePurchasePerAddress: 0,
            //     presaleMerkleRoot: bytes32(0)
            // })
        });
        // weth = new WETH();

        // Deploy Variable Supply Auction module
        auctions = new VariableSupplyAuction();
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
    }

    function test_DropInitial() public {
        assertEq(drop.name(), "Test Mutant Ninja Turtles");
        assertEq(drop.symbol(), "TMNT");

        assertEq(drop.owner(), address(seller));
        assertEq(drop.getRoleMember(drop.MINTER_ROLE(), 0), address(auctions));

        (
            // IMetadataRenderer renderer,
            uint64 editionSize,
            uint16 royaltyBPS,
            address payable fundsRecipient
        ) = drop.config();

        // assertEq(address(renderer), address(dummyRenderer));
        assertEq(editionSize, 1);
        assertEq(royaltyBPS, 1000);
        assertEq(fundsRecipient, payable(sellerFundsRecipient));
    }

    /*//////////////////////////////////////////////////////////////
                        CREATE AUCTION
    //////////////////////////////////////////////////////////////*/

    function testGas_CreateAuction() public {
        // NOTE this basic setup can be applied to tests via setupBasicAuction modifier
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: block.timestamp,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    function test_CreateAuction_WhenInstant() public setupBasicAuction {
        (
            address sellerStored,
            uint256 minimumRevenue,
            address sellerFundsRecipientStored,
            uint256 startTime,
            uint256 endOfBidPhase,
            uint256 endOfRevealPhase,
            uint256 endOfSettlePhase,
            uint96 totalBalance
        ) = auctions.auctionForDrop(address(drop));

        assertEq(sellerStored, address(seller));
        assertEq(minimumRevenue, 1 ether);
        assertEq(sellerFundsRecipientStored, address(sellerFundsRecipient));
        assertEq(startTime, uint32(block.timestamp));
        assertEq(endOfBidPhase, uint32(block.timestamp + 3 days));
        assertEq(endOfRevealPhase, uint32(block.timestamp + 3 days + 2 days));
        assertEq(endOfSettlePhase, uint32(block.timestamp + 3 days + 2 days + 1 days));
        assertEq(totalBalance, uint96(0));
    }

    function test_CreateAuction_WhenFuture() public {
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumRevenue: 1 ether,
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
        ) = auctions.auctionForDrop(address(drop));

        assertEq(startTime, 1 days);
        assertEq(endOfBidPhase, 1 days + 3 days);
        assertEq(endOfRevealPhase, 1 days + 3 days + 2 days);
        assertEq(endOfSettlePhase, 1 days + 3 days + 2 days + 1 days);
    }

    function testEvent_createAuction() public {
        Auction memory auction = Auction({
            seller: address(seller),
            minimumRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(block.timestamp),
            endOfBidPhase: uint32(block.timestamp + 3 days),
            endOfRevealPhase: uint32(block.timestamp + 3 days + 2 days),
            endOfSettlePhase: uint32(block.timestamp + 3 days + 2 days + 1 days),
            totalBalance: uint96(0)
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionCreated(address(drop), auction);

        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: block.timestamp,
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
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: 1 days,
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
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(0),
            _startTime: 1 days,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL AUCTION
    //////////////////////////////////////////////////////////////*/

    // TODO cancelAuction

    /*//////////////////////////////////////////////////////////////
                        PLACE BID
    //////////////////////////////////////////////////////////////*/

    function test_PlaceBid_WhenSingle() public setupBasicAuction {  
        bytes32 commitment = genSealedBid(1 ether, bytes32("setec astronomy"));

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 totalBalance
        ) = auctions.auctionForDrop(address(drop));
        (bytes32 commitmentStored, ) = auctions.bidOf(address(drop), address(bidder1));

        assertEq(address(auctions).balance, 1 ether);
        assertEq(totalBalance, 1 ether);
        assertEq(auctions.balanceOf(address(drop), address(bidder1)), 1 ether);
        assertEq(commitmentStored, commitment);
    }

    function test_PlaceBid_WhenMultiple() public setupBasicAuction {
        // NOTE sealed bid amount can be less than sent ether amount (allows for hiding bid amount until reveal)
        bytes32 commitment1 = genSealedBid(1 ether, bytes32("setec astronomy"));
        bytes32 commitment2 = genSealedBid(1 ether, bytes32("too many secrets"));
        bytes32 commitment3 = genSealedBid(1 ether, bytes32("cray tomes on set"));

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);
        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), commitment2);
        vm.prank(address(bidder3));
        auctions.placeBid{value: 3 ether}(address(drop), commitment3);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 totalBalance
        ) = auctions.auctionForDrop(address(drop));
        (bytes32 commitmentStored1, ) = auctions.bidOf(address(drop), address(bidder1));
        (bytes32 commitmentStored2, ) = auctions.bidOf(address(drop), address(bidder2));
        (bytes32 commitmentStored3, ) = auctions.bidOf(address(drop), address(bidder3));

        assertEq(address(auctions).balance, 6 ether);
        assertEq(totalBalance, 6 ether);
        assertEq(auctions.balanceOf(address(drop), address(bidder1)), 1 ether);
        assertEq(auctions.balanceOf(address(drop), address(bidder2)), 2 ether);
        assertEq(auctions.balanceOf(address(drop), address(bidder3)), 3 ether);
        assertEq(commitmentStored1, commitment1);
        assertEq(commitmentStored2, commitment2);
        assertEq(commitmentStored3, commitment3);
    }

    function testEvent_PlaceBid_WhenMultiple() public setupBasicAuction {
        Auction memory auction = Auction({
            seller: address(seller),
            minimumRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(block.timestamp),
            endOfBidPhase: uint32(block.timestamp + 3 days),
            endOfRevealPhase: uint32(block.timestamp + 3 days + 2 days),
            endOfSettlePhase: uint32(block.timestamp + 3 days + 2 days + 1 days),
            totalBalance: uint96(1 ether) // expect this totalBalance in event based on first bid
        });

        bytes32 commitment1 = genSealedBid(1 ether, bytes32("setec astronomy"));
        bytes32 commitment2 = genSealedBid(1 ether, bytes32("too many secrets"));
        bytes32 commitment3 = genSealedBid(1 ether, bytes32("cray tomes on set"));

        vm.expectEmit(true, true, true, true);
        emit AuctionBid(address(drop), address(bidder1), auction);

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment1);

        auction.totalBalance = 3 ether; // 2 ether more from bidder 2

        vm.expectEmit(true, true, true, true);
        emit AuctionBid(address(drop), address(bidder2), auction);

        vm.prank(address(bidder2));
        auctions.placeBid{value: 2 ether}(address(drop), commitment2);

        auction.totalBalance = 6 ether; // 3 ether more from bidder 3

        vm.expectEmit(true, true, true, true);
        emit AuctionBid(address(drop), address(bidder3), auction);

        vm.prank(address(bidder3));
        auctions.placeBid{value: 3 ether}(address(drop), commitment3);
    }

    function testRevert_PlaceBid_WhenAuctionDoesNotExist() public {
        vm.expectRevert("AUCTION_DOES_NOT_EXIST");

        bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInRevealPhase() public setupBasicAuction {
        vm.warp(3 days + 1 seconds); // reveal phase

        vm.expectRevert("BIDS_ONLY_ALLOWED_DURING_BID_PHASE");

        bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenAuctionInSettlePhase() public setupBasicAuction {
        vm.warp(3 days + 2 days + 1 seconds); // settle phase

        vm.expectRevert("BIDS_ONLY_ALLOWED_DURING_BID_PHASE");

        bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenBidderAlreadyPlacedBid() public setupBasicAuction {
        bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);

        vm.expectRevert("ALREADY_PLACED_BID_IN_AUCTION");

        vm.prank(address(bidder1));
        auctions.placeBid{value: 1 ether}(address(drop), commitment);
    }

    function testRevert_PlaceBid_WhenNoEtherIncluded() public setupBasicAuction {
        vm.expectRevert("VALID_BIDS_MUST_INCLUDE_ETHER");

        bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
        vm.prank(address(bidder1));
        auctions.placeBid(address(drop), commitment);
    }

    // TODO once settleAuction is written
    // function testRevert_PlaceBid_WhenAuctionIsCompleted() public setupBasicAuction {
        
    // }

    // TODO once cancelAuction is written
    // function testRevert_PlaceBid_WhenAuctionIsCancelled() public setupBasicAuction {
        
    // }

    // TODO revist – test may become relevant if we move minter role granting into TransferHelper
    // function testRevert_PlaceBid_WhenSellerDidNotApproveModule() public setupBasicAuction {
    //     seller.setApprovalForModule(address(auctions), false);

    //     vm.expectRevert("module has not been approved by user");

    //     bytes32 commitment = genSealedBid(1 ether, "setec astronomy");
    //     vm.prank(address(bidder1));
    //     auctions.placeBid{value: 1 ether}(address(drop), commitment);
    // }

    /*//////////////////////////////////////////////////////////////
                        REVEAL BID
    //////////////////////////////////////////////////////////////*/

    // TODO revealBid

    /*//////////////////////////////////////////////////////////////
                        FAILURE TO REVEAL BID
    //////////////////////////////////////////////////////////////*/

    // TODO bidder failure to reveal bid sad paths

    /*//////////////////////////////////////////////////////////////
                        SETTLE AUCTION
    //////////////////////////////////////////////////////////////*/

    // TODO settleAuction

    /*//////////////////////////////////////////////////////////////
                        FAILURE TO SETTLE AUCTION
    //////////////////////////////////////////////////////////////*/

    // TODO seller failure to settle auction sad paths

    /*//////////////////////////////////////////////////////////////
                        TEST HELPERS
    //////////////////////////////////////////////////////////////*/

    // TODO improve modifier pattern to include parameters (could combine w/ fuzzing)

    modifier setupBasicAuction() {
        vm.prank(address(seller));
        auctions.createAuction({
            _tokenContract: address(drop),
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: block.timestamp,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        _;
    }

    function genSealedBid(uint256 _amount, bytes32 _salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_amount, _salt));
    }

    /*//////////////////////////////////////////////////////////////
                        TODO use better pattern to DRY up
    //////////////////////////////////////////////////////////////*/

    struct Auction {
        address seller;
        uint96 minimumRevenue;
        address sellerFundsRecipient;
        uint32 startTime;
        uint32 endOfBidPhase;
        uint32 endOfRevealPhase;
        uint32 endOfSettlePhase;
        uint96 totalBalance;
    }

    struct Bid {
        bytes32 commitment;
        uint256 revealed;
    }

    event AuctionCreated(address indexed drop, Auction auction);
    event AuctionBid(address indexed tokenContract, address indexed bidder, Auction auction);    
}
