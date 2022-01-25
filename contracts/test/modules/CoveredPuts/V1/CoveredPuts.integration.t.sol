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

/// @title CoveredPutsV1IntegrationTest
/// @notice Integration Tests for Covered Put Options v1.0
contract CoveredPutsV1IntegrationTest is DSTest {
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

        // Mint buyer token
        token.mint(address(buyer), 0);

        // Users swap 50 ETH <> 50 WETH
        vm.prank(address(seller));
        weth.deposit{value: 50 ether}();

        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve CoveredPuts module
        seller.setApprovalForModule(address(puts), true);
        buyer.setApprovalForModule(address(puts), true);

        // Users approve ERC20TransferHelper
        vm.prank(address(seller));
        weth.approve(address(erc20TransferHelper), 50 ether);

        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ ETH PURCHASED PUT OPTION ------------ ///

    function runETHPurchase() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);
    }

    function test_ETHPurchaseIntegration() public {
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeBuyerBalance = address(buyer).balance;

        runETHPurchase();

        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterBuyerBalance = address(buyer).balance;

        require(beforeSellerBalance - afterSellerBalance == 0.5 ether);
        require(beforeBuyerBalance - afterBuyerBalance == 0.5 ether);
    }

    /// ------------ ETH EXERCISED PUT OPTION ------------ ///

    function runETHExercise() public {
        vm.prank(address(seller));
        puts.createPut{value: 1 ether}(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        puts.buyPut{value: 0.5 ether}(address(token), 0, 1, address(0), 0.5 ether, 1 ether);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.exercisePut(address(token), 0, 1);
    }

    function test_ETHExerciseIntegration() public {
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        address beforeTokenOwner = token.ownerOf(0);

        runETHExercise();

        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        address afterTokenOwner = token.ownerOf(0);

        require(beforeSellerBalance - afterSellerBalance == 0.5 ether);
        require(afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance == 0.05 ether);
        require(afterBuyerBalance - beforeBuyerBalance == 0.45 ether);
        require(beforeTokenOwner == address(buyer) && afterTokenOwner == address(seller));
    }

    /// ------------ ERC-20 PURCHASED PUT OPTION ------------ ///

    function runERC20Purchase() public {
        vm.prank(address(seller));
        puts.createPut(address(token), 0, 0.5 ether, 1 ether, 1 days, address(weth));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        puts.buyPut(address(token), 0, 1, address(weth), 0.5 ether, 1 ether);
    }

    function test_ERC20PurchaseIntegration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(seller));
        uint256 beforeBuyerBalance = weth.balanceOf(address(buyer));

        runERC20Purchase();

        uint256 afterSellerBalance = weth.balanceOf(address(seller));
        uint256 afterBuyerBalance = weth.balanceOf(address(buyer));

        require(beforeSellerBalance - afterSellerBalance == 0.5 ether);
        require(beforeBuyerBalance - afterBuyerBalance == 0.5 ether);
    }

    /// ------------ ERC-20 EXERCISED PUT OPTION ------------ ///

    function runERC20Exercise() public {
        vm.prank(address(seller));
        puts.createPut(address(token), 0, 0.5 ether, 1 ether, 1 days, address(weth));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        puts.buyPut(address(token), 0, 1, address(weth), 0.5 ether, 1 ether);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        puts.exercisePut(address(token), 0, 1);
    }

    function test_ERC20ExerciseIntegration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(seller));
        uint256 beforeBuyerBalance = weth.balanceOf(address(buyer));
        uint256 beforeRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        address beforeTokenOwner = token.ownerOf(0);

        runERC20Exercise();

        uint256 afterSellerBalance = weth.balanceOf(address(seller));
        uint256 afterBuyerBalance = weth.balanceOf(address(buyer));
        uint256 afterRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        address afterTokenOwner = token.ownerOf(0);

        require(beforeSellerBalance - afterSellerBalance == 0.5 ether);
        require(afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance == 0.05 ether);
        require(afterBuyerBalance - beforeBuyerBalance == 0.45 ether);
        require(beforeTokenOwner == address(buyer) && afterTokenOwner == address(seller));
    }
}
