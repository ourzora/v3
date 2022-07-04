// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {CoveredPutsEth} from "../../../../../modules/CoveredPuts/Core/ETH/CoveredPutsEth.sol";
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

/// @title CoveredPutsEthTest
/// @notice Unit Tests for ETH Covered Put Options
contract CoveredPutsEthTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    CoveredPutsEth internal puts;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal buyer;
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
        buyer = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy ETH Covered Put Options
        puts = new CoveredPutsEth(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(puts));

        // Set user balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(buyer), 100 ether);

        // Mint put buyer token
        token.mint(address(buyer), 0);

        // Buyer approve CoveredPutsEth module
        buyer.setApprovalForModule(address(puts), true);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    function test_CreatePut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        (address putSeller, uint256 putPremium, address putBuyer, uint256 putStrike, uint256 putExpiry) = puts.puts(address(token), 0, 1);

        require(putSeller == address(seller));
        require(putBuyer == address(0));
        require(putPremium == 0.5 ether);
        require(putStrike == 1 ether);
        require(putExpiry == 1 days);
    }

    function test_CreateMaxPremium() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 2**96 - 1, 1 days);

        (, uint256 putPremium, , , ) = puts.puts(address(token), 0, 1);

        require(putPremium == 2**96 - 1);
    }

    ///                                                          ///
    ///                        CANCEL PUT                        ///
    ///                                                          ///

    function test_CancelPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);
        vm.prank(address(seller));
        puts.cancelPut(address(token), 0, 1);
    }

    function testRevert_CancelPutMustBeSeller() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);
        vm.expectRevert("ONLY_SELLER");
        puts.cancelPut(address(token), 0, 1);
    }

    function testRevert_CancelPutAlreadyPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.prank(address(seller));
        vm.expectRevert("PURCHASED");
        puts.cancelPut(address(token), 0, 1);
    }

    ///                                                          ///
    ///                         BUY PUT                          ///
    ///                                                          ///

    function test_BuyPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        (, , address putBuyer, , ) = puts.puts(address(token), 0, 1);

        require(putBuyer == address(buyer));
    }

    function testRevert_BuyPutAlreadyPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(1 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(2 hours);

        vm.prank(address(buyer));
        vm.expectRevert("PURCHASED");
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);
    }

    function testRevert_BuyPutExpired() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("EXPIRED");
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);
    }

    ///                                                          ///
    ///                       EXERCISE PUT                       ///
    ///                                                          ///

    function test_ExercisePut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(buyer));
        puts.exercisePut(address(token), 0, 1);

        require(token.ownerOf(0) == address(seller));
    }

    function testRevert_ExercisePutMustBeBuyer() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(23 hours);
        vm.expectRevert("ONLY_BUYER");
        puts.exercisePut(address(token), 0, 1);
    }

    function testRevert_ExercisePutExpired() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(1 days + 1 seconds);

        vm.prank(address(buyer));
        vm.expectRevert("EXPIRED");
        puts.exercisePut(address(token), 0, 1);
    }

    ///                                                          ///
    ///                        RECLAIM PUT                       ///
    ///                                                          ///

    function test_ReclaimPut() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(1 days + 1 seconds);

        uint256 beforeBalance = address(seller).balance;

        vm.prank(address(seller));
        puts.reclaimPut(address(token), 0, 1);

        uint256 afterBalance = address(seller).balance;
        require(afterBalance - beforeBalance == 1 ether);
    }

    function testRevert_ReclaimPutMustBeSeller() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);
        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);
        vm.warp(1 days + 1 seconds);
        vm.expectRevert("ONLY_SELLER");
        puts.reclaimPut(address(token), 0, 1);
    }

    function testRevert_ReclaimPutNotPurchased() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(seller));
        vm.expectRevert("NOT_PURCHASED");
        puts.reclaimPut(address(token), 0, 1);
    }

    function testRevert_ReclaimPutActive() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 days);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, 1 ether);

        vm.warp(23 hours);

        vm.prank(address(seller));
        vm.expectRevert("NOT_EXPIRED");
        puts.reclaimPut(address(token), 0, 1);
    }
}
