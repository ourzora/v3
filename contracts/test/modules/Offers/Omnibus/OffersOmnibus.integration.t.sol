// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {OffersOmnibus} from "../../../../modules/Offers/Omnibus/OffersOmnibus.sol";
import {OffersDataStorage} from "../../../../modules/Offers/Omnibus/OffersDataStorage.sol";
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

/// @title OffersV1IntegrationTest
/// @notice Integration Tests for Offers v1.0
contract OffersOmnibusIntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    OffersOmnibus internal offers;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal buyer;
    Zorb internal finder;
    Zorb internal royaltyRecipient;
    Zorb internal listingFeeRecipient;

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
        listingFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Offers v1.0
        offers = new OffersOmnibus(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(offers));

        // Set buyer balance
        vm.deal(address(buyer), 100 ether);

        // Mint buyer token
        token.mint(address(seller), 0);

        // buyer swap 50 ETH <> 50 WETH
        vm.prank(address(buyer));
        weth.deposit{value: 50 ether}();

        // Users approve Offers module
        buyer.setApprovalForModule(address(offers), true);
        seller.setApprovalForModule(address(offers), true);

        // Buyer approve ERC20TransferHelper
        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // Seller approve ERC721TransferHelper
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ ETH Offer ------------ ///

    function runETH() public {
        vm.prank(address(buyer));
        uint256 id = offers.createOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 0, 100, 200, address(listingFeeRecipient));

        vm.prank(address(seller));
        offers.fillOffer(address(token), 0, id, 1 ether, address(0), address(finder));
    }

    function test_ETHIntegration() public {
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeFinderBalance = address(finder).balance;
        uint256 beforeListingFeeRecipientBalance = address(listingFeeRecipient).balance;
        address beforeTokenOwner = token.ownerOf(0);
        runETH();
        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterFinderBalance = address(finder).balance;
        uint256 afterListingFeeRecipientBalance = address(listingFeeRecipient).balance;
        address afterTokenOwner = token.ownerOf(0);
        // 1 ETH withdrawn from buyer
        require((beforeBuyerBalance - afterBuyerBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 100 bps finders fee (Remaining 0.95 ETH * finders fee = 0.0095 ETH)
        require((afterFinderBalance - beforeFinderBalance) == 0.0095 ether);
        // 200 bps listing fee (Remaining 0.95 ETH * listing fee = 0.019 ETH)
        require((afterListingFeeRecipientBalance - beforeListingFeeRecipientBalance) == 0.019 ether);
        // Remaining 0.855 ETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.9215 ether);
        // NFT transferred to buyer
        require((beforeTokenOwner == address(seller)) && afterTokenOwner == address(buyer));
    }

    // /// ------------ ERC-20 Offer ------------ ///

    function runERC20() public {
        vm.prank(address(buyer));
        uint256 id = offers.createOffer(address(token), 0, address(weth), 1 ether, 0, 100, 200, address(listingFeeRecipient));

        vm.prank(address(seller));
        offers.fillOffer(address(token), 0, id, 1 ether, address(weth), address(finder));
    }

    function test_ERC20Integration() public {
        uint256 beforeSellerBalance = weth.balanceOf(address(seller));
        uint256 beforeBuyerBalance = weth.balanceOf(address(buyer));
        uint256 beforeRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 beforeFinderBalance = weth.balanceOf(address(finder));
        uint256 beforeListingFeeRecipientBalance = weth.balanceOf(address(listingFeeRecipient));
        address beforeTokenOwner = token.ownerOf(0);
        runERC20();
        uint256 afterSellerBalance = weth.balanceOf(address(seller));
        uint256 afterBuyerBalance = weth.balanceOf(address(buyer));
        uint256 afterRoyaltyRecipientBalance = weth.balanceOf(address(royaltyRecipient));
        uint256 afterFinderBalance = weth.balanceOf(address(finder));
        uint256 afterListingFeeRecipientBalance = weth.balanceOf(address(listingFeeRecipient));
        address afterTokenOwner = token.ownerOf(0);

        // 1 WETH withdrawn from seller
        assertEq((beforeBuyerBalance - afterBuyerBalance), 1 ether);
        // 0.05 WETH creator royalty
        assertEq((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance), 0.05 ether);
        // 0.095 WETH finders fee (0.95 WETH * 10% finders fee)
        assertEq((afterFinderBalance - beforeFinderBalance), 0.0095 ether);
        assertEq((afterListingFeeRecipientBalance - beforeListingFeeRecipientBalance), 0.019 ether);

        // Remaining 0.9215 WETH paid to buyer
        assertEq((afterSellerBalance - beforeSellerBalance), 0.9215 ether);
        // NFT transferred to seller
        require((beforeTokenOwner == address(seller)) && afterTokenOwner == address(buyer));
    }
}
