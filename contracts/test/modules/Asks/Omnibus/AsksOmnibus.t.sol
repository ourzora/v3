// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AsksOmnibus} from "../../../../modules/Asks/Omnibus/AsksOmnibus.sol";
import {AsksDataStorage} from "../../../../modules/Asks/Omnibus/AsksDataStorage.sol";
import {Zorb} from "../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../utils/modules/RoyaltyEngine.sol";
import {TestERC20} from "../../../utils/tokens/TestERC20.sol";
import {TestERC721} from "../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../utils/tokens/WETH.sol";
import {VM} from "../../../utils/VM.sol";

/// @title ReserveAuctionFindersErc20Test
/// @notice Unit Tests for Reserve Auction Finders ERC-20
contract AsksOmnibusTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    AsksOmnibus internal asks;
    TestERC20 internal erc20;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal finder;
    Zorb internal listingFeeRecipient;
    Zorb internal royaltyRecipient;
    Zorb internal buyer;

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
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));
        listingFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        erc20 = new TestERC20();
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction Finders ERC-20
        asks = new AsksOmnibus(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(buyer), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Mint bidder 2^96 ERC-20 tokens
        erc20.mint(address(buyer), 2**96);

        // Bidder swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve ReserveAuction module
        seller.setApprovalForModule(address(asks), true);
        buyer.setApprovalForModule(address(asks), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Bidder approve ERC20TransferHelper for TestERC20
        vm.prank(address(buyer));
        erc20.approve(address(erc20TransferHelper), 2**96);

        // Bidder approve ERC20TransferHelper for WETH
        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ CREATE ASK ------------ ///

    function test_CreateAskMinimal() public {
        vm.prank(address(seller));
        asks.createAsk(
            address(token),
            0,
            0,
            1 ether,
            address(seller),
            address(0),
            address(0),
            0,
            AsksDataStorage.ListingFee({listingFeeBps: 0, listingFeeRecipient: address(0)}),
            AsksDataStorage.TokenGate({token: address(0), minAmount: 0})
        );
    }

    function test_CreateAskMinimalTiny() public {
        vm.prank(address(seller));
        asks.createAskMinimal(address(token), 0, 1 ether);
    }

    function test_CreateAsk() public {
        vm.prank(address(seller));
        asks.createAsk(
            address(token),
            0,
            uint96(block.timestamp + 1 days),
            1 ether,
            address(sellerFundsRecipient),
            address(weth),
            address(buyer),
            1000,
            AsksDataStorage.ListingFee({listingFeeBps: 1, listingFeeRecipient: address(listingFeeRecipient)}),
            AsksDataStorage.TokenGate({token: address(erc20), minAmount: 1})
        );
    }
}
