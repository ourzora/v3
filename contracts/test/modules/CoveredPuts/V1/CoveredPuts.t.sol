// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {CoveredPutsV1} from "../../../../modules/CoveredPuts/V1/CoveredPutsV1.sol";
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

/// @title CoveredPutsV1Test
/// @notice Unit Tests for Covered Put Options v1.0
contract CoveredPutsV1Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    CoveredPutsV1 internal puts;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal buyer;
    Zorb internal finder;
    Zorb internal royaltyRecipient;

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
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Covered Put Options v1.0
        puts = new CoveredPutsV1(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(puts));

        // Set user balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(buyer), 100 ether);

        // Mint put buyer token
        token.mint(address(buyer), 0);

        // Buyer swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve CoveredPuts module
        seller.setApprovalForModule(address(puts), true);
        buyer.setApprovalForModule(address(puts), true);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Buyer approve ERC20TransferHelper
        vm.prank(address(seller));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ CREATE PUT ------------ ///

    function testGas_CreatePut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));
    }

    function test_CreatePut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        (address putSeller, address putBuyer, address putCurrency, uint256 putPremium, uint256 putStrike, uint256 putExpiry) = puts.puts(
            address(token),
            0,
            1
        );

        require(putSeller == address(seller));
        require(putBuyer == address(0));
        require(putCurrency == address(0));
        require(putPremium == 0.5 ether);
        require(putStrike == 1 ether);
        require(putExpiry == 1 days);
    }

    function testRevert_CannotCreatePutOnOwnNFT() public {
        vm.prank(address(buyer));
        vm.expectRevert("createPut cannot create put on owned NFT");
        puts.createPut(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));
    }

    function testRevert_CreatePutMustAttachStrikeFunds() public {
        vm.prank(address(seller));
        vm.expectRevert("_handleIncomingTransfer msg value less than expected amount");
        puts.createPut(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));
    }

    /// ------------ CANCEL PUT ------------ ///

    function test_CancelPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(seller));
        puts.cancelPut(address(token), 0, 1);
    }

    function testRevert_CancelPutMustBeSeller() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.expectRevert("cancelPut must be seller");
        puts.cancelPut(address(token), 0, 1);
    }

    function testRevert_CancelPutDoesNotExist() public {
        vm.expectRevert("cancelPut must be seller");
        puts.cancelPut(address(token), 0, 1);
    }

    function testRevert_CancelPutAlreadyPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.prank(address(seller));
        vm.expectRevert("cancelPut put has been purchased");
        puts.cancelPut(address(token), 0, 1);
    }

    /// ------------ BUY PUT ------------ ///

    function test_BuyPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        (, address putBuyer, , , , ) = puts.puts(address(token), 0, 1);
        require(putBuyer == address(buyer));
    }

    function testRevert_BuyPutDoesNotExist() public {
        vm.expectRevert("buyPut put does not exist");
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);
    }

    function testRevert_BuyPutAlreadyPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(11 hours);

        vm.expectRevert("buyPut put already purchased");
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);
    }

    function testRevert_BuyPutExpired() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("buyPut put expired");
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);
    }

    /// ------------ EXERCISE PUT ------------ ///

    function test_ExercisePut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        puts.exercisePut(address(token), 0, 1);

        require(token.ownerOf(0) == address(seller));
    }

    function testRevert_ExercisePutMustBeBuyer() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(23 hours);

        vm.expectRevert("exercisePut must be buyer");
        puts.exercisePut(address(token), 0, 1);
    }

    function testRevert_ExercisePutMustOwnToken() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        token.transferFrom(address(buyer), address(this), 0);

        vm.prank(address(buyer));
        vm.expectRevert("exercisePut must own token");
        puts.exercisePut(address(token), 0, 1);
    }

    function testRevert_ExercisePutExpired() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("exercisePut put expired");
        puts.exercisePut(address(token), 0, 1);
    }

    /// ------------ RECLAIM PUT ------------ ///

    function test_ReclaimPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(1 days + 1 seconds);

        uint256 beforeBalance = address(seller).balance;

        vm.prank(address(seller));
        puts.reclaimPut(address(token), 0, 1);

        uint256 afterBalance = address(seller).balance;
        require(afterBalance - beforeBalance == 1 ether);
    }

    function testRevert_ReclaimPutMustBeSeller() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.expectRevert("reclaimPut must be seller");
        puts.reclaimPut(address(token), 0, 1);
    }

    function testRevert_ReclaimPutNotPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(seller));
        vm.expectRevert("reclaimPut put not purchased");
        puts.reclaimPut(address(token), 0, 1);
    }

    function testRevert_ReclaimPutActive() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(seller));
        vm.expectRevert("reclaimPut put is active");
        puts.reclaimPut(address(token), 0, 1);
    }
}
