// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import {VariableSupplyAuction} from "../../../modules/VariableSupplyAuction/VariableSupplyAuction.sol";

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
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    VariableSupplyAuction internal auctions;
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

        // Deploy Variable Supply Auction module
        auctions = new VariableSupplyAuction();
        registrar.registerModule(address(auctions));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);
        vm.deal(address(otherBidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 1);

        // Users approve module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);
        otherBidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /*//////////////////////////////////////////////////////////////
                        Create Auction
    //////////////////////////////////////////////////////////////*/

    function testGas_CreateAuction() public {
        vm.prank(address(seller));
        auctions.createAuction({
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: block.timestamp,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    function test_CreateAuction_WhenInstant() public {
        Auction memory auction = Auction({
            minimumRevenue: 1 ether,
            sellerFundsRecipient: address(sellerFundsRecipient),
            startTime: uint32(block.timestamp),
            endOfBidPhase: uint32(block.timestamp + 3 days),
            endOfRevealPhase: uint32(block.timestamp + 3 days + 2 days),
            endOfSettlePhase: uint32(block.timestamp + 3 days + 2 days + 1 days),
            firstBidTime: uint32(0 days)
        });

        vm.expectEmit(true, true, true, true);
        emit AuctionCreated(address(seller), auction);

        vm.prank(address(seller));
        auctions.createAuction({
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: block.timestamp,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        (
            uint256 minimumRevenue,
            address sellerFundsRecipientReturned,
            uint256 startTime,
            uint256 endOfBidPhase,
            uint256 endOfRevealPhase,
            uint256 endOfSettlePhase,
            uint256 firstBidTime
            // bids
        ) = auctions.auctionForSeller(address(seller));

        assertEq(minimumRevenue, auction.minimumRevenue);
        assertEq(sellerFundsRecipientReturned, auction.sellerFundsRecipient);
        assertEq(startTime, auction.startTime);
        assertEq(endOfBidPhase, auction.endOfBidPhase);
        assertEq(endOfRevealPhase, auction.endOfRevealPhase);
        assertEq(endOfSettlePhase, auction.endOfSettlePhase);
        assertEq(firstBidTime, 0);
        // bids
    }

    function test_CreateAuction_WhenFuture() public {
        vm.prank(address(seller));
        auctions.createAuction({
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: 1 days,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        (, , uint32 startTime, , , , ) = auctions.auctionForSeller(address(seller));
        require(startTime == 1 days);
    }

    function testRevert_CreateAuction_WhenSellerHasLiveAuction() public {
        vm.prank(address(seller));
        auctions.createAuction({
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(sellerFundsRecipient),
            _startTime: 1 days,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });

        vm.expectRevert("ONLY_ONE_LIVE_AUCTION_PER_SELLER");

        vm.prank(address(seller));
        auctions.createAuction({
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
            _minimumRevenue: 1 ether,
            _sellerFundsRecipient: address(0),
            _startTime: 1 days,
            _bidPhaseDuration: 3 days,
            _revealPhaseDuration: 2 days,
            _settlePhaseDuration: 1 days
        });
    }

    /*//////////////////////////////////////////////////////////////
                        NOT DRY -- TODO Use better pattern
    //////////////////////////////////////////////////////////////*/

    struct Auction {
        uint96 minimumRevenue;
        address sellerFundsRecipient;
        uint32 startTime;
        uint32 endOfBidPhase;
        uint32 endOfRevealPhase;
        uint32 endOfSettlePhase;
        uint32 firstBidTime;
        // bids
    }

    event AuctionCreated(address indexed seller, Auction auction);
}
