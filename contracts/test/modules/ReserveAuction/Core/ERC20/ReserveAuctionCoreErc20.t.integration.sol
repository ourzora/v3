// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionCoreErc20} from "../../../../../modules/ReserveAuction/Core/ERC20/ReserveAuctionCoreErc20.sol";
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

/// @title ReserveAuctionCoreErc20IntegrationTest
/// @notice Integration Tests for Reserve Auction Core ERC-20
contract ReserveAuctionCoreErc20IntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    ReserveAuctionCoreErc20 internal auctions;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal operator;
    Zorb internal royaltyRecipient;
    Zorb internal bidder;
    Zorb internal otherBidder;
    Zorb internal protocolFeeRecipient;

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
        bidder = new Zorb(address(ZMM));
        otherBidder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));
        protocolFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Reserve Auction Core ERC-20
        auctions = new ReserveAuctionCoreErc20(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(auctions));

        // Set module fee
        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(auctions), address(protocolFeeRecipient), 1);

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);
        vm.deal(address(otherBidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Bidder swap 50 ETH <> 50 WETH
        vm.prank(address(bidder));
        weth.deposit{value: 50 ether}();

        // otherBidder swap 50 ETH <> 50 WETH
        vm.prank(address(otherBidder));
        weth.deposit{value: 50 ether}();

        // Users approve module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);
        otherBidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Bidder approve ERC20TransferHelper
        vm.prank(address(bidder));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // otherBidder approve ERC20TransferHelper
        vm.prank(address(otherBidder));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    function runERC20() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 days, 0.1 ether, address(sellerFundsRecipient), 0, address(weth));

        vm.warp(1 hours);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 0.1 ether);

        vm.warp(10 hours);
        vm.prank(address(otherBidder));
        auctions.createBid(address(token), 0, 0.5 ether);

        vm.warp(1 days);
        vm.prank(address(bidder));
        auctions.createBid(address(token), 0, 1 ether);

        vm.warp(1 days + 1 hours);
        auctions.settleAuction(address(token), 0);
    }

    function test_ERC20Integration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 beforeBidderBalance = weth.balanceOf(address(bidder));
        uint256 beforeOtherBidderBalance = weth.balanceOf(address(otherBidder));
        uint256 beforeRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 beforeProtocolFeeRecipient = weth.balanceOf(address(protocolFeeRecipient));
        address beforeTokenOwner = token.ownerOf(0);

        runERC20();

        uint256 afterSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 afterBidderBalance = weth.balanceOf(address(bidder));
        uint256 afterOtherBidderBalance = weth.balanceOf(address(otherBidder));
        uint256 afterRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 afterProtocolFeeRecipient = weth.balanceOf(address(protocolFeeRecipient));
        address afterTokenOwner = token.ownerOf(0);

        // 1 ETH withdrawn from winning bidder
        require((beforeBidderBalance - afterBidderBalance) == 1 ether);
        // Losing bidder refunded
        require(beforeOtherBidderBalance == afterOtherBidderBalance);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 1 bps protocol fee (Remaining 0.95 ETH * 0.01% protocol fee = 0.000095 ETH)
        require((afterProtocolFeeRecipient - beforeProtocolFeeRecipient) == 0.000095 ether);
        // Remaining 0.949905 ETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.949905 ether);
        // NFT transferred to winning bidder
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(bidder));
    }
}
