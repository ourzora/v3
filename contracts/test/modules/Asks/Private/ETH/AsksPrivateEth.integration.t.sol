// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AsksPrivateEth} from "../../../../../modules/Asks/Private/ETH/AsksPrivateEth.sol";
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

/// @title AsksPrivateEthIntegrationTest
/// @notice Integration Tests for Asks Private ETH
contract AsksPrivateEthIntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    AsksPrivateEth internal asks;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal operator;
    Zorb internal buyer;
    Zorb internal finder;
    Zorb internal sellerFundsRecipient;
    Zorb internal royaltyRecipient;
    Zorb internal protocolFeeRecipient;

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
        operator = new Zorb(address(ZMM));
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));
        protocolFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Asks Private ETH
        asks = new AsksPrivateEth(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

        // Set module fee
        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(asks), address(protocolFeeRecipient), 1);

        // Set buyer balance
        vm.deal(address(buyer), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Buyer swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve Asks module
        seller.setApprovalForModule(address(asks), true);
        buyer.setApprovalForModule(address(asks), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    function runETH() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(buyer));

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(address(token), 0);
    }

    function test_ETHIntegration() public {
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeProtocolFeeRecipientBalance = address(protocolFeeRecipient).balance;
        address beforeTokenOwner = token.ownerOf(0);

        runETH();

        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterProtocolFeeRecipientBalance = address(protocolFeeRecipient).balance;
        address afterTokenOwner = token.ownerOf(0);

        // 1 ETH withdrawn from buyer
        require((beforeBuyerBalance - afterBuyerBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 1 bps protocol fee (Remaining 0.95 ETH * 0.01% protocol fee = 0.000095 ETH)
        require((afterProtocolFeeRecipientBalance - beforeProtocolFeeRecipientBalance) == 0.000095 ether);
        // Remaining 0.949905 ETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.949905 ether);
        // NFT transferred to buyer
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(buyer));
    }
}
