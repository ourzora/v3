// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {CollectionOffersV1} from "../../../../modules/CollectionOffers/V1/CollectionOffersV1.sol";
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

/// @title CollectionOffersV1IntegrationTest
/// @notice Integration Tests for CollectionOffersV1
contract CollectionOffersV1IntegrationTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    CollectionOffersV1 internal offers;
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

        // Deploy Collection Offers v1.0
        offers = new CollectionOffersV1(
            address(erc20TransferHelper),
            address(erc721TransferHelper),
            address(royaltyEngine),
            address(ZPFS),
            address(weth)
        );
        registrar.registerModule(address(offers));

        // Set seller balance
        vm.deal(address(seller), 100 ether);

        // Mint buyer token
        token.mint(address(buyer), 0);

        // Users approve Collection Offers module
        seller.setApprovalForModule(address(offers), true);
        buyer.setApprovalForModule(address(offers), true);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ ETH COLLECTION OFFER ------------ ///

    function offer() public {
        vm.prank(address(seller));
        offers.createOffer{value: 1 ether}(address(token));
    }

    function fill() public {
        vm.prank(address(seller));
        offers.createOffer{value: 1 ether}(address(token));

        vm.prank(address(buyer));
        offers.fillOffer(address(token), 0, 1 ether, address(finder));
    }

    function test_WithdrawOfferFromSeller() public {
        uint256 beforeBalance = address(seller).balance;
        offer();
        uint256 afterBalance = address(seller).balance;

        require(beforeBalance - afterBalance == 1 ether);
    }

    function test_WithdrawOfferIncreaseFromSeller() public {
        uint256 beforeBalance = address(seller).balance;

        offer();

        // Increase initial offer to 2 ETH
        vm.prank(address(seller));
        offers.setOfferAmount{value: 1 ether}(address(token), 1, 2 ether);

        uint256 afterBalance = address(seller).balance;

        require(beforeBalance - afterBalance == 2 ether);
    }

    function test_RefundOfferDecreaseToSeller() public {
        uint256 beforeBalance = address(seller).balance;

        offer();

        // Decrease initial offer to 0.5 ETH
        vm.prank(address(seller));
        offers.setOfferAmount(address(token), 1, 0.5 ether);

        uint256 afterBalance = address(seller).balance;

        require(beforeBalance - afterBalance == 0.5 ether);
    }

    function test_ETHIntegration() public {
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeFinderBalance = address(finder).balance;
        address beforeTokenOwner = token.ownerOf(0);

        fill();

        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterFinderBalance = address(finder).balance;
        address afterTokenOwner = token.ownerOf(0);

        // 1 ETH withdrawn from seller
        require((beforeSellerBalance - afterSellerBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 100 bps finders fee (Remaining 0.95 ETH * 10% finders fee = 0.0095 ETH)
        require((afterFinderBalance - beforeFinderBalance) == 0.0095 ether);
        // Remaining 0.9405 ETH paid to buyer
        require((afterBuyerBalance - beforeBuyerBalance) == 0.9405 ether);
        // NFT transferred to seller
        require((beforeTokenOwner == address(buyer)) && afterTokenOwner == address(seller));
    }
}
