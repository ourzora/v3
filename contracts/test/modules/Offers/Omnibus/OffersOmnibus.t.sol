// SPDX-License-Identifier: GPL-3.0
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

/// @title OffersOmnibusTest
/// @notice Unit Tests for Offers Omnibus
contract OffersOmnibusTest is DSTest {
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

    Zorb internal maker;
    Zorb internal taker;
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
        maker = new Zorb(address(ZMM));
        taker = new Zorb(address(ZMM));
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

        // Set maker balance
        vm.deal(address(maker), 100 ether);

        // Mint taker token
        token.mint(address(taker), 0);

        // Maker swap 50 ETH <> 50 WETH
        vm.prank(address(maker));
        weth.deposit{value: 50 ether}();

        // Users approve Offers module
        maker.setApprovalForModule(address(offers), true);
        taker.setApprovalForModule(address(offers), true);

        // Maker approve ERC20TransferHelper
        vm.prank(address(maker));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // Taker approve ERC721TransferHelper
        vm.prank(address(taker));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ CREATE NFT OFFER ------------ ///

    function testGas_CreateOffer() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            uint96(block.timestamp + 100000),
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
    }

    function testGas_CreateOfferMinimal() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
    }

    function test_CreateETHOffer() public {
        uint256 makerBalanceBefore = address(maker).balance;
        uint256 makerWethBalanceBefore = weth.balanceOf(address(maker));
        vm.prank(address(maker));
        offers.createOffer{value: 1 ether}(
            address(token),
            0,
            address(0),
            1 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
        uint256 makerBalanceAfter = address(maker).balance;
        uint256 makerWethBalanceAfter = weth.balanceOf(address(maker));
        assertEq(makerBalanceBefore - makerBalanceAfter, 1 ether);
        assertEq(makerWethBalanceAfter - makerWethBalanceBefore, 1 ether);
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 1 ether);
        assertEq(offer.maker, address(maker));
        assertEq(offer.expiry, 0);
        assertEq(offer.findersFeeBps, 100);
        assertEq(offer.currency, address(0));
        assertEq(offer.listingFee.listingFeeRecipient, address(listingFeeRecipient));
        assertEq(offer.listingFee.listingFeeBps, 200);
    }

    function test_CreateERC20Offer() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 1 ether);
        assertEq(offer.maker, address(maker));
        assertEq(offer.expiry, 0);
        assertEq(offer.findersFeeBps, 100);
        assertEq(offer.currency, address(weth));
        assertEq(offer.listingFee.listingFeeRecipient, address(listingFeeRecipient));
        assertEq(offer.listingFee.listingFeeBps, 200);
    }

    function test_CreateOfferMinimal() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 1 ether);
        assertEq(offer.maker, address(maker));
        assertEq(offer.expiry, 0);
        assertEq(offer.findersFeeBps, 0);
        assertEq(offer.currency, address(0));
        assertEq(offer.listingFee.listingFeeRecipient, address(0));
        assertEq(offer.listingFee.listingFeeBps, 0);
    }

    function test_CreateOfferWithExpiry() public {
        uint256 makerBalanceBefore = address(maker).balance;
        uint256 makerWethBalanceBefore = weth.balanceOf(address(maker));
        vm.prank(address(maker));
        uint96 start = uint96(block.timestamp);
        uint96 tomorrow = start + 1 days;
        offers.createOffer{value: 1 ether}(
            address(token),
            0,
            address(0),
            1 ether,
            tomorrow,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
        vm.warp(tomorrow + 1 days);
        vm.startPrank(address(taker));
        vm.expectRevert("Ask has expired");
        offers.fillOffer(address(token), 0, 1, 1 ether, address(0), address(0));
        vm.warp(start + 1 hours);
        offers.fillOffer(address(token), 0, 1, 1 ether, address(0), address(0));
    }

    function testFail_CannotCreateOfferWithoutAttachingFunds() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(0),
            1 ether,
            0,
            0,
            OffersDataStorage.ListingFee({listingFeeBps: 0, listingFeeRecipient: address(0)})
        );
    }

    function testFail_CannotCreateOfferWithInvalidFindersFeeBps() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            0,
            10001,
            OffersDataStorage.ListingFee({listingFeeBps: 0, listingFeeRecipient: address(0)})
        );
    }

    function testFail_CannotCreateOfferWithInvalidFindersAndListingFeeBps() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            0,
            5000,
            OffersDataStorage.ListingFee({listingFeeBps: 5001, listingFeeRecipient: address(listingFeeRecipient)})
        );
    }

    function testFail_CannotCreateOfferWithInvalidExpiry() public {
        vm.prank(address(maker));
        vm.warp(1000);
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            500,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
    }

    function testFail_CannotCreateERC20OfferWithMsgValue() public {
        vm.prank(address(maker));
        offers.createOffer{value: 1 ether}(
            address(token),
            0,
            address(weth),
            1 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
    }

    function testFail_CannotCreateERC20OfferInsufficientBalance() public {
        vm.prank(address(maker));
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1000 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
    }

    function testFail_CannotCreateETHOfferInsufficientWethAllowance() public {
        vm.startPrank(address(maker));
        weth.approve(address(erc20TransferHelper), 0);
        offers.createOffer{value: 1 ether}(
            address(token),
            0,
            address(0),
            1 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
        vm.stopPrank();
    }

    function testFail_CannotCreateERC20OfferInsufficientAllowance() public {
        vm.startPrank(address(maker));
        weth.approve(address(erc20TransferHelper), 0);
        offers.createOffer(
            address(token),
            0,
            address(weth),
            1 ether,
            0,
            100,
            OffersDataStorage.ListingFee({listingFeeBps: 200, listingFeeRecipient: address(listingFeeRecipient)})
        );
        vm.stopPrank();
    }

    /// ------------ SET NFT OFFER ------------ ///

    function test_IncreaseETHOffer() public {
        uint256 wethBalanceBefore = weth.balanceOf(address(maker));
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        uint256 wethBalanceAfterCreate = weth.balanceOf(address(maker));
        vm.warp(1 hours);
        offers.setOfferAmount{value: 1 ether}(address(token), 0, 1, address(0), 2 ether);
        vm.stopPrank();
        uint256 wethBalanceAfterUpdate = weth.balanceOf(address(maker));
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 2 ether);
        assertEq(wethBalanceAfterCreate - wethBalanceBefore, 1 ether);
        assertEq(wethBalanceAfterUpdate - wethBalanceBefore, 2 ether);
    }

    function test_DecreaseETHOffer() public {
        uint256 wethBalanceBefore = weth.balanceOf(address(maker));
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 2 ether}(address(token), 0);
        uint256 wethBalanceAfterCreate = weth.balanceOf(address(maker));
        vm.warp(1 hours);
        offers.setOfferAmount(address(token), 0, 1, address(0), 1 ether);
        vm.stopPrank();
        uint256 wethBalanceAfterUpdate = weth.balanceOf(address(maker));
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 1 ether);
        assertEq(wethBalanceAfterCreate - wethBalanceBefore, 2 ether);
        assertEq(wethBalanceAfterCreate, wethBalanceAfterUpdate);
    }

    function test_IncreaseETHOfferWithERC20() public {
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.warp(1 hours);
        offers.setOfferAmount(address(token), 0, 1, address(weth), 2 ether);
        vm.stopPrank();
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 2 ether);
        assertEq(offer.currency, address(weth));
        assertEq(address(offers).balance, 0 ether);
    }

    function test_DecreaseETHOfferWithERC20() public {
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.warp(1 hours);
        offers.setOfferAmount(address(token), 0, 1, address(weth), 0.5 ether);
        vm.stopPrank();
        OffersDataStorage.FullOffer memory offer = offers.getFullOffer(address(token), 0, 1);
        assertEq(offer.amount, 0.5 ether);
        assertEq(offer.currency, address(weth));
        assertEq(address(offers).balance, 0 ether);
    }

    function testRevert_OnlySellerCanUpdateOffer() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.expectRevert("CALLER_NOT_MAKER");
        offers.setOfferAmount(address(token), 0, 1, address(0), 0.5 ether);
    }

    function testRevert_CannotIncreaseEthOfferWithoutAttachingNecessaryFunds() public {
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 0.1 ether}(address(token), 0);
        vm.expectRevert("INSUFFICIENT_BALANCE");
        offers.setOfferAmount(address(token), 0, 1, address(0), 51 ether);
        vm.stopPrank();
    }

    function testRevert_CannotUpdateOfferWithPreviousAmount() public {
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.warp(1 hours);
        vm.expectRevert("SAME_OFFER");
        offers.setOfferAmount{value: 1 ether}(address(token), 0, 1, address(0), 1 ether);
        vm.stopPrank();
    }

    function testRevert_CannotUpdateInactiveOffer() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.prank(address(taker));
        offers.fillOffer(address(token), 0, 1, 1 ether, address(0), address(finder));
        vm.prank(address(maker));
        vm.expectRevert("CALLER_NOT_MAKER");
        offers.setOfferAmount(address(token), 0, 1, address(0), 0.5 ether);
    }

    /// ------------ CANCEL NFT OFFER ------------ ///

    function test_CancelNFTOffer() public {
        vm.startPrank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        (uint256 beforeAmount, , ) = offers.offers(address(token), 0, 1);
        require(beforeAmount == 1 ether);
        offers.cancelOffer(address(token), 0, 1);
        (uint256 afterAmount, , ) = offers.offers(address(token), 0, 1);
        require(afterAmount == 0);
        vm.stopPrank();
    }

    function testRevert_CannotCancelInactiveOffer() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.prank(address(taker));
        offers.fillOffer(address(token), 0, 1, 1 ether, address(0), address(finder));
        vm.prank(address(maker));
        vm.expectRevert("CALLER_NOT_MAKER");
        offers.cancelOffer(address(token), 0, 1);
    }

    function testRevert_OnlySellerCanCancelOffer() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.expectRevert("CALLER_NOT_MAKER");
        offers.cancelOffer(address(token), 0, 1);
    }

    // /// ------------ FILL NFT OFFER ------------ ///

    function test_FillNFTOffer() public {
        vm.prank(address(maker));
        offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        address beforeTokenOwner = token.ownerOf(0);
        vm.prank(address(taker));
        offers.fillOffer(address(token), 0, 1, 1 ether, address(0), address(finder));
        address afterTokenOwner = token.ownerOf(0);
        require(beforeTokenOwner == address(taker) && afterTokenOwner == address(maker));
    }

    function testRevert_OnlyTokenHolderCanFillOffer() public {
        vm.prank(address(maker));
        uint256 id = offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.expectRevert("fillOffer must be token owner");
        offers.fillOffer(address(token), 0, id, 1 ether, address(0), address(finder));
    }

    function testRevert_CannotFillInactiveOffer() public {
        vm.prank(address(maker));
        uint256 id = offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.prank(address(taker));
        offers.fillOffer(address(token), 0, id, 1 ether, address(0), address(finder));
        vm.prank(address(taker));
        vm.expectRevert("fillOffer must be active offer");
        offers.fillOffer(address(token), 0, id, 1 ether, address(0), address(finder));
    }

    function testRevert_AcceptCurrencyMustMatchOffer() public {
        vm.prank(address(maker));
        uint256 id = offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.prank(address(taker));
        vm.expectRevert("fillOffer _currency & _amount must match offer");
        offers.fillOffer(address(token), 0, id, 1 ether, address(weth), address(finder));
    }

    function testRevert_AcceptAmountMustMatchOffer() public {
        vm.prank(address(maker));
        uint256 id = offers.createOfferMinimal{value: 1 ether}(address(token), 0);
        vm.prank(address(taker));
        vm.expectRevert("fillOffer _currency & _amount must match offer");
        offers.fillOffer(address(token), 0, id, 0.5 ether, address(0), address(finder));
    }
}
