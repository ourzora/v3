// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {DutchAuctionV1} from "../../../../modules/DutchAuction/V1/DutchAuctionV1.sol";
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

/// @title DutchAuctionV1IntegrationTest
/// @notice Integration Tests for Dutch Auction v1.0
contract DutchAuctionV1IntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    DutchAuctionV1 internal auctions;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal sellerFundsRecipient;
    Zorb internal finder;
    Zorb internal royaltyRecipient;
    Zorb internal bidder;
    Zorb internal otherBidder;

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
        bidder = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Dutch Auction v1.0
        auctions = new DutchAuctionV1(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(auctions));

        // Set balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(bidder), 100 ether);

        // Mint seller token
        token.mint(address(seller), 0);

        // Bidder swap 50 ETH <> 50 WETH
        vm.prank(address(bidder));
        weth.deposit{value: 50 ether}();

        // Users approve ReserveAuction module
        seller.setApprovalForModule(address(auctions), true);
        bidder.setApprovalForModule(address(auctions), true);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        // Bidder approve ERC20TransferHelper
        vm.prank(address(bidder));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ ETH AUCTION ------------ ///

    function runETH() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(0), 0, 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    function test_ETHIntegration() public {
        uint256 beforeSellerBalance = address(sellerFundsRecipient).balance;
        uint256 beforeBidderBalance = address(bidder).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeFinderBalance = address(finder).balance;
        address beforeTokenOwner = token.ownerOf(0);

        runETH();

        uint256 afterSellerBalance = address(sellerFundsRecipient).balance;
        uint256 afterBidderBalance = address(bidder).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterFinderBalance = address(finder).balance;
        address afterTokenOwner = token.ownerOf(0);

        // 1 ETH withdrawn from winning bidder
        require((beforeBidderBalance - afterBidderBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 1000 bps finders fee (Remaining 0.95 ETH * 10% finders fee = 0.095 ETH)
        require((afterFinderBalance - beforeFinderBalance) == 0.095 ether);
        // Remaining 0.855 ETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.855 ether);
        // NFT transferred to winning bidder
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(bidder));
    }

    /// ------------ ERC-20 AUCTION ------------ ///

    function runERC20() public {
        vm.prank(address(seller));
        auctions.createAuction(address(token), 0, 1 ether, 0.2 ether, payable(address(sellerFundsRecipient)), 1000, address(weth), 0, 0);

        vm.prank(address(bidder));
        auctions.createBid{value: 1 ether}(address(token), 0, 1 ether, address(finder));
    }

    function test_ERC20Integration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 beforeBidderBalance = weth.balanceOf(address(bidder));
        uint256 beforeRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 beforeFinderBalance = weth.balanceOf(address(finder));
        address beforeTokenOwner = token.ownerOf(0);

        runERC20();

        uint256 afterSellerBalance = weth.balanceOf(address(sellerFundsRecipient));
        uint256 afterBidderBalance = weth.balanceOf(address(bidder));
        uint256 afterRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 afterFinderBalance = weth.balanceOf(address(finder));
        address afterTokenOwner = token.ownerOf(0);

        // 1 WETH withdrawn from buyer
        require((beforeBidderBalance - afterBidderBalance) == 1 ether);
        // 0.05 WETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 0.095 WETH finders fee paid to finder (remaining 0.95 WETH * 1000 bps finders fee)
        require((afterFinderBalance - beforeFinderBalance) == 0.095 ether);
        // Final 0.855 WETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.855 ether);
        // NFT transferred to buyer
        require((beforeTokenOwner == address(seller)) && afterTokenOwner == address(bidder));
    }
}
