// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {CoveredCallsEth} from "../../../../../modules/CoveredCalls/Core/ETH/CoveredCallsEth.sol";
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

/// @title CoveredCallsEthTest
/// @notice Unit Tests for ETH Covered Call Options
contract CoveredCallsEthTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    CoveredCallsEth internal calls;
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
        otherSeller = new Zorb(address(ZMM));
        buyer = new Zorb(address(ZMM));
        otherBuyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Covered Calls ETH
        calls = new CoveredCallsEth(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(calls));

        // Set user balances
        vm.deal(address(buyer), 100 ether);
        vm.deal(address(otherBuyer), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Users approve CoveredCalls module
        seller.setApprovalForModule(address(calls), true);
        buyer.setApprovalForModule(address(calls), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    ///                                                          ///
    ///                       CREATE CALL                        ///
    ///                                                          ///

    function test_CreateCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        (address callSeller, uint256 callPremium, address callBuyer, uint256 callStrike, uint256 callExpiry) = calls.callForNFT(address(token), 0);

        require(callSeller == address(seller));
        require(callBuyer == address(0));
        require(callPremium == 0.5 ether);
        require(callStrike == 1 ether);
        require(callExpiry == 1 days);
    }

    function test_CreateCallAsOperator() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(operator), true);

        vm.startPrank(address(operator));

        ZMM.setApprovalForModule(address(calls), true);
        token.setApprovalForAll(address(erc721TransferHelper), true);

        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.stopPrank();
    }

    function test_CreateWithMaxPrices() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 2**96 - 1, 2**96 - 1, 1 days);

        (, uint256 callPremium, , uint256 callStrike, ) = calls.callForNFT(address(token), 0);

        require(callStrike == 2**96 - 1);
        require(callPremium == 2**96 - 1);
    }

    function testRevert_CreateCallMustBeOwnerOrOperator() public {
        vm.expectRevert("ONLY_TOKEN_OWNER_OR_OPERATOR");
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);
    }

    ///                                                          ///
    ///                       CANCEL CALL                        ///
    ///                                                          ///

    function test_CancelCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(seller));
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CancelCallMustBeSeller() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.expectRevert("ONLY_SELLER_OR_TOKEN_OWNER");
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CancelCallMustExist() public {
        vm.expectRevert("ONLY_SELLER_OR_TOKEN_OWNER");
        calls.cancelCall(address(token), 0);
    }

    function testRevert_CannotCancelPurchasedCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.prank(address(seller));
        vm.expectRevert("PURCHASED");
        calls.cancelCall(address(token), 0);
    }

    ///                                                          ///
    ///                        BUY CALL                          ///
    ///                                                          ///

    function test_BuyCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        (, , address beforeCallBuyer, , ) = calls.callForNFT(address(token), 0);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        (, , address afterCallBuyer, , ) = calls.callForNFT(address(token), 0);

        require(beforeCallBuyer == address(0) && afterCallBuyer == address(buyer));
        require(token.ownerOf(0) == address(calls));
    }

    function testRevert_BuyCallDoesNotExist() public {
        vm.expectRevert("INVALID_CALL");
        calls.buyCall(address(token), 0, 1 ether);
    }

    function testRevert_BuyCallAlreadyPurchased() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.expectRevert("INVALID_PURCHASE");
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);
    }

    function testRevert_BuyCallExpired() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(1 days + 1 minutes);

        vm.expectRevert("INVALID_CALL");
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);
    }

    ///                                                          ///
    ///                      EXERCISE CALL                       ///
    ///                                                          ///

    function test_ExerciseCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        calls.exerciseCall{value: 1 ether}(address(token), 0);

        require(token.ownerOf(0) == address(buyer));
    }

    function testRevert_ExerciseCallMustBeBuyer() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(23 hours);

        vm.expectRevert("ONLY_BUYER");
        calls.exerciseCall{value: 1 ether}(address(token), 0);
    }

    function testRevert_ExerciseCallExpired() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("INVALID_EXERCISE");
        calls.exerciseCall{value: 1 ether}(address(token), 0);
    }

    function testRevert_MustMatchStrike() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        vm.expectRevert("MUST_MATCH_STRIKE");
        calls.exerciseCall{value: 0.99 ether}(address(token), 0);
    }

    ///                                                          ///
    ///                       RECLAIM CALL                       ///
    ///                                                          ///

    function test_ReclaimCall() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(seller));
        calls.reclaimCall(address(token), 0);

        require(token.ownerOf(0) == address(seller));
    }

    function testRevert_ReclaimCallMustBeSeller() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.expectRevert("ONLY_SELLER");
        calls.reclaimCall(address(token), 0);
    }

    function testRevert_ReclaimCallNotPurchased() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(seller));
        vm.expectRevert("INVALID_RECLAIM");
        calls.reclaimCall(address(token), 0);
    }

    function testRevert_ReclaimCallActive() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(seller));
        vm.expectRevert("ACTIVE_OPTION");
        calls.reclaimCall(address(token), 0);
    }
}
