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

/// @title CoveredCallsV1IntegrationTest
/// @notice Integration Tests for Covered Call Options v1.0
contract CoveredCallsV1IntegrationTest is DSTest {
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

    /// ------------ ETH PURCHASED CALL OPTION ------------ ///

    function runETHPurchase() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);
    }

    function test_ETHPurchaseIntegration() public {
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeBuyerBalance = address(buyer).balance;
        address beforeTokenOwner = token.ownerOf(0);

        runETHPurchase();

        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterBuyerBalance = address(buyer).balance;
        address afterTokenOwner = token.ownerOf(0);

        require(afterSellerBalance - beforeSellerBalance == 0.5 ether);
        require(beforeBuyerBalance - afterBuyerBalance == 0.5 ether);
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(calls));
    }

    /// ------------ ETH EXERCISED CALL OPTION ------------ ///

    function runETHExercise() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(0));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.exerciseCall{value: 1 ether}(address(token), 0);
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

        require(beforeBuyerBalance - afterBuyerBalance == 1.5 ether);
        require(afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance == 0.05 ether);
        require(afterSellerBalance - beforeSellerBalance == 1.45 ether);
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(buyer));
    }

    /// ------------ ERC-20 PURCHASED CALL OPTION ------------ ///

    function runERC20Purchase() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(weth));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall(address(token), 0);
    }

    function test_ERC20PurchaseIntegration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(seller));
        uint256 beforeBuyerBalance = weth.balanceOf(address(buyer));
        address beforeTokenOwner = token.ownerOf(0);

        runERC20Purchase();

        uint256 afterSellerBalance = weth.balanceOf(address(seller));
        uint256 afterBuyerBalance = weth.balanceOf(address(buyer));
        address afterTokenOwner = token.ownerOf(0);

        require(afterSellerBalance - beforeSellerBalance == 0.5 ether);
        require(beforeBuyerBalance - afterBuyerBalance == 0.5 ether);
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(calls));
    }

    /// ------------ ERC-20 EXERCISED CALL OPTION ------------ ///

    function runERC20Exercise() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days, address(weth));

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall(address(token), 0);

        vm.warp(10 hours);

        vm.prank(address(buyer));
        calls.exerciseCall(address(token), 0);
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

        require(beforeBuyerBalance - afterBuyerBalance == 1.5 ether);
        require(afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance == 0.05 ether);
        require(afterSellerBalance - beforeSellerBalance == 1.45 ether);
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(buyer));
    }
}
