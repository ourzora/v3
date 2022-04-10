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

/// @title CoveredCallsEthIntegrationTest
/// @notice Integration Tests for ETH Covered Call Options
contract CoveredCallsEthIntegrationTest is DSTest {
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

        // Deploy Covered Calls ETH
        calls = new CoveredCallsEth(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(calls));

        // Set user balances
        vm.deal(address(buyer), 100 ether);

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
    ///                      PURCHASED CALL                      ///
    ///                                                          ///

    function runETHPurchase() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);
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

    ///                                                          ///
    ///                      EXERCISED CALL                      ///
    ///                                                          ///

    function runETHExercise() public {
        vm.prank(address(seller));
        calls.createCall(address(token), 0, 0.5 ether, 1 ether, 1 days);

        vm.warp(1 hours);

        vm.prank(address(buyer));
        calls.buyCall{value: 0.5 ether}(address(token), 0, 1 ether);

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
}
