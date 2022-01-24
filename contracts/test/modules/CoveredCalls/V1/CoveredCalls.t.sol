// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {CoveredCallsV1} from "../../../../modules/CoveredCalls/V1/CoveredCallsV1.sol";
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

/// @title CoveredCallsV1Test
/// @notice Unit Tests for Covered Call Options v1.0
contract CoveredCallsV1Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    CoveredCallsV1 internal calls;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal otherSeller;
    Zorb internal buyer;
    Zorb internal otherBuyer;
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
        sellerFundsRecipient = new Zorb(address(ZMM));
        operator = new Zorb(address(ZMM));
        otherSeller = new Zorb(address(ZMM));
        buyer = new Zorb(address(ZMM));
        otherBuyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Covered Call Options v1.0
        calls = new CoveredCallsV1(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(calls));

        // Set user balances
        vm.deal(address(buyer), 100 ether);
        vm.deal(address(otherBuyer), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Buyer swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve CoveredCalls module
        seller.setApprovalForModule(address(calls), true);
        buyer.setApprovalForModule(address(calls), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Buyer approve ERC20TransferHelper
        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ CREATE CALL ------------ ///

    function testGas_CreateCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));
    }

    function test_CreateCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        (
            address callSeller,
            address callBuyer,
            address callCurrency,
            uint256 callPremium,
            uint256 callStrike,
            uint256 callExpiry
        ) = calls.callForNFT(address(token), 0);

        require(callSeller == address(seller));
        require(callBuyer == address(0));
        require(callCurrency == address(0));
        require(callPremium == 0.5 ether);
        require(callStrike == 1 ether);
        require(callExpiry == 1 days);
    }

    function test_CreateCallWithOperator() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(operator), true);

        vm.startPrank(address(operator));

        ZMM.setApprovalForModule(address(calls), true);
        token.setApprovalForAll(address(erc721TransferHelper), true);

        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.stopPrank();
    }

    function test_CreateCallAndCancelInactiveCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.prank(address(seller));
        (address beforeSeller, , , , , ) = calls.callForNFT(address(token), 0);

        require(beforeSeller == address(seller));

        vm.warp(10 hours);

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(operator), 0);

        vm.startPrank(address(operator));

        ZMM.setApprovalForModule(address(calls), true);
        token.setApprovalForAll(address(erc721TransferHelper), true);
        calls.createCall(address(token), 0, 2 ether, 10 ether, 3 days, address(0));

        vm.stopPrank();

        (address afterSeller, , , , , ) = calls.callForNFT(address(token), 0);
        require(afterSeller == address(operator));
    }

    function testRevert_CreateCallMustBeOwnerOrOperator() public {
        vm.expectRevert("createCall must be token owner or operator");
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));
    }

    function testRevert_CreateCallMustApproveERC721TransferHelper() public {
        vm.startPrank(address(seller));

        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.expectRevert("createCall must approve ERC721TransferHelper as operator");
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.stopPrank();
    }

    function testRevert_CreateCallExpirationMustBeFutureTime() public {
        vm.prank(address(seller));
        vm.expectRevert("createCall _expiration must be future time");
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 0, address(0));
    }

    /// ------------ CANCEL CALL ------------ ///

    function test_CancelCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(seller));
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CancelCallMustBeSeller() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.expectRevert("cancelCall must be seller or invalid call");
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CancelCallMustExist() public {
        vm.expectRevert("cancelCall call does not exist");
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CannotCancelPurchasedCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.prank(address(seller));
        vm.expectRevert("cancelCall call has been purchased");
        calls.cancelCall(address(token), 0);
    }

    /// ------------ BUY CALL ------------ ///

    function test_BuyCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        (, address beforeCallBuyer, , , , ) = calls.callForNFT(address(token), 0);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        (, address afterCallBuyer, , , , ) = calls.callForNFT(address(token), 0);

        require(beforeCallBuyer == address(0) && afterCallBuyer == address(buyer));
        require(token.ownerOf(0) == address(calls));
    }

    function testRevert_BuyCallDoesNotExist() public {
        vm.expectRevert("buyCall call does not exist");
        calls.buyCall(address(token), 0);
    }

    function testRevert_BuyCallAlreadyPurchased() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.expectRevert("buyCall call already purchased");
        calls.buyCall{value: 0.5 ether}(address(token), 0);
    }

    function testRevert_BuyCallExpired() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 days + 1 minutes);

        vm.expectRevert("buyCall call expired");
        calls.buyCall{value: 0.5 ether}(address(token), 0);
    }

    /// ------------ EXERCISE CALL ------------ ///

    function test_ExerciseCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        calls.exerciseCall{value: 1 ether}(address(token), 0);

        require(token.ownerOf(0) == address(buyer));
    }

    function testRevert_ExerciseCallMustBeBuyer() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(23 hours);

        vm.expectRevert("exerciseCall must be buyer");
        calls.exerciseCall{value: 1 ether}(address(token), 0);
    }

    function testRevert_ExerciseCallExpired() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("exerciseCall call expired");
        calls.exerciseCall{value: 1 ether}(address(token), 0);
    }

    /// ------------ RECLAIM CALL ------------ ///

    function test_ReclaimCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(seller));
        calls.reclaimCall(address(token), 0);

        require(token.ownerOf(0) == address(seller));
    }

    function testRevert_ReclaimCallMustBeSeller() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(1 days + 1 seconds);

        vm.expectRevert("reclaimCall must be seller");
        calls.reclaimCall(address(token), 0);
    }

    function testRevert_ReclaimCallNotPurchased() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(seller));
        vm.expectRevert("reclaimCall call not purchased");
        calls.reclaimCall(address(token), 0);
    }

    function testRevert_ReclaimCallActive() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(23 hours);

        vm.prank(address(seller));
        vm.expectRevert("reclaimCall call is active");
        calls.reclaimCall(address(token), 0);
    }
}
