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

/// @title CollectionOffersV1Test
/// @notice Unit Tests for CollectionOffersV1
contract CollectionOffersV1Test is DSTest {
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
    Zorb internal seller2;
    Zorb internal seller3;
    Zorb internal seller4;
    Zorb internal seller5;
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
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        seller = new Zorb(address(ZMM));
        seller2 = new Zorb(address(ZMM));
        seller3 = new Zorb(address(ZMM));
        seller4 = new Zorb(address(ZMM));
        seller5 = new Zorb(address(ZMM));
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

        // Set user balances
        vm.deal(address(seller), 100 ether);
        vm.deal(address(seller2), 100 ether);
        vm.deal(address(seller3), 100 ether);
        vm.deal(address(seller4), 100 ether);
        vm.deal(address(seller5), 100 ether);

        // Mint buyer token
        token.mint(address(buyer), 0);

        // Users approve Collection Offers module
        seller.setApprovalForModule(address(offers), true);
        seller2.setApprovalForModule(address(offers), true);
        seller3.setApprovalForModule(address(offers), true);
        seller4.setApprovalForModule(address(offers), true);
        seller5.setApprovalForModule(address(offers), true);
        buyer.setApprovalForModule(address(offers), true);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ HELPERS ------------ ///

    function loadOffers() public {
        // First offer
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));
        // Ceiling offer
        vm.prank(address(seller2));
        offers.createCollectionOffer{value: 2 ether}(address(token));
        // Floor offer
        vm.prank(address(seller3));
        offers.createCollectionOffer{value: 0.5 ether}(address(token));
        // Middle offer
        vm.prank(address(seller4));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        // Floor to Ceiling order: id3 --> id4 --> id1 --> id2
    }

    /// ------------ CREATE COLLECTION OFFER ------------ ///

    function testGas_CreateFirstCollectionOffer() public {
        offers.createCollectionOffer{value: 1 ether}(address(token));
    }

    function test_CreateCollectionOffer() public {
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        (address offeror, uint256 amount, uint256 id, uint256 _prevId, uint256 _nextId) = offers.offers(address(token), 1);

        require(offeror == address(seller));
        require(id == 1);
        require(amount == 1 ether);
        require(_prevId == 0);
        require(_nextId == 0);

        uint256 floorId = offers.floorOfferId(address(token));
        uint256 floorAmt = offers.floorOfferAmount(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));
        uint256 ceilingAmt = offers.ceilingOfferAmount(address(token));

        require(floorId == 1);
        require(floorAmt == 1 ether);
        require(ceilingId == 1);
        require(ceilingAmt == 1 ether);
    }

    function test_CreateCeilingOffer() public {
        // First offer
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));
        // Ceiling offer
        vm.prank(address(seller2));
        offers.createCollectionOffer{value: 2 ether}(address(token));

        (address offeror1, uint256 amount1, uint256 id1, uint256 _prevId1, uint256 _nextId1) = offers.offers(address(token), 1);
        (address offeror2, uint256 amount2, uint256 id2, uint256 _prevId2, uint256 _nextId2) = offers.offers(address(token), 2);

        require(offeror1 == address(seller) && offeror2 == address(seller2));
        require(amount1 == 1 ether && amount2 == 2 ether);
        // Ensure floor prevId is 0 and ceiling nextId is 0
        require(_prevId1 == 0 && _nextId2 == 0);
        // Ensure floor nextId is ceiling id and ceiling prevId is floor id
        require(_nextId1 == 2 && _prevId2 == 1);

        uint256 floorId = offers.floorOfferId(address(token));
        uint256 floorAmt = offers.floorOfferAmount(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));
        uint256 ceilingAmt = offers.ceilingOfferAmount(address(token));

        require(floorId == id1);
        require(floorAmt == amount1);
        require(ceilingId == id2);
        require(ceilingAmt == amount2);
    }

    function test_CreateFloorOffer() public {
        // First offer
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));
        // Ceiling offer
        vm.prank(address(seller2));
        offers.createCollectionOffer{value: 2 ether}(address(token));
        // Floor offer
        vm.prank(address(seller3));
        offers.createCollectionOffer{value: 0.5 ether}(address(token));

        (address offeror1, uint256 amount1, uint256 id1, uint256 _prevId1, uint256 _nextId1) = offers.offers(address(token), 1);
        (address offeror2, uint256 amount2, uint256 id2, uint256 _prevId2, uint256 _nextId2) = offers.offers(address(token), 2);
        (address offeror3, uint256 amount3, uint256 id3, uint256 _prevId3, uint256 _nextId3) = offers.offers(address(token), 3);

        // Ensure sellers and amounts are valid
        require(offeror1 == address(seller) && offeror2 == address(seller2) && offeror3 == address(seller3));
        require(amount1 == 1 ether && amount2 == 2 ether && amount3 == 0.5 ether);

        // Ensure floor to ceiling order is: id3 --> id1 --> id2
        require(_prevId3 == 0 && _nextId2 == 0);
        require(_nextId3 == id1 && _prevId1 == id3);
        require(_nextId1 == id2 && _prevId2 == id1);

        uint256 floorId = offers.floorOfferId(address(token));
        uint256 floorAmt = offers.floorOfferAmount(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));
        uint256 ceilingAmt = offers.ceilingOfferAmount(address(token));

        require(floorId == id3);
        require(floorAmt == amount3);
        require(ceilingId == id2);
        require(ceilingAmt == amount2);
    }

    function test_CreateMiddleOffer() public {
        loadOffers();

        // Floor to ceiling order: id3 --> id4 --> id1 --> id2
        (address offeror4, uint256 amount4, , uint256 _prevId4, uint256 _nextId4) = offers.offers(address(token), 4);
        uint256 floorId = offers.floorOfferId(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));

        // Ensure seller and amount are valid
        require(offeror4 == address(seller4) && amount4 == 1 ether);

        // Ensure placement between offer 3 and 1
        require(_nextId4 == 1 && _prevId4 == 3);
        // Ensure floor and ceiling ids are valid
        require(ceilingId == 2 && floorId == 3);
    }

    function testRevert_MustAttachFundsToCreateOffer() public {
        vm.expectRevert("createCollectionOffer msg value must be greater than 0");
        offers.createCollectionOffer(address(token));
    }

    /// ------------ SET COLLECTION OFFER AMOUNT ------------ ///

    function test_IncreaseFloorToNewCeiling() public {
        loadOffers();

        // Increase floor offer to new ceiling
        vm.prank(address(seller3));
        offers.setCollectionOfferAmount{value: 4.5 ether}(address(token), 3, 5 ether);

        // Updated order: id4 --> id1 --> id2 --> id3
        (, uint256 amount3, , uint256 _prevId3, uint256 _nextId3) = offers.offers(address(token), 3);
        uint256 floorId = offers.floorOfferId(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));

        // Ensure book is updated with floor as new ceiling
        require(ceilingId == 3 && floorId == 4);
        require(_prevId3 == 2 && _nextId3 == 0);
        require(amount3 == 5 ether);
    }

    function test_IncreaseFloorToMiddle() public {
        loadOffers();

        // Increase floor offer to equal ceiling
        vm.prank(address(seller3));
        offers.setCollectionOfferAmount{value: 1.5 ether}(address(token), 3, 2 ether);

        // Updated order: id4 --> id1 --> id3 --> id2
        (, uint256 amount3, , uint256 _prevId3, uint256 _nextId3) = offers.offers(address(token), 3);
        uint256 floorId = offers.floorOfferId(address(token));
        uint256 ceilingId = offers.ceilingOfferId(address(token));

        // Ensure book is updated wrt time priority
        require(ceilingId == 2 && floorId == 4);
        require(_prevId3 == 1 && _nextId3 == 2);
        require(amount3 == 2 ether);
    }

    function test_IncreaseCeilingInPlace() public {
        loadOffers();

        vm.prank(address(seller2));
        offers.setCollectionOfferAmount{value: 3 ether}(address(token), 2, 5 ether);

        (, uint256 amount2, , uint256 _prevId2, uint256 _nextId2) = offers.offers(address(token), 2);
        uint256 ceilingId = offers.ceilingOfferId(address(token));

        require(ceilingId == 2);
        require(_prevId2 == 1 && _nextId2 == 0);
        require(amount2 == 5 ether);
    }

    function testRevert_UpdateOfferMustBeSeller() public {
        loadOffers();

        vm.prank(address(seller2));
        vm.expectRevert("setCollectionOfferAmount offer must be active & msg sender must be seller");
        offers.setCollectionOfferAmount(address(token), 1, 0.5 ether);
    }

    /// ------------ SET COLLECTION OFFER FINDERS FEE ------------ ///

    function test_UpdateFindersFee() public {
        vm.startPrank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        vm.warp(1 hours);

        offers.setCollectionOfferFindersFee(address(token), 1, 1000);

        vm.stopPrank();

        require(offers.findersFeeOverrides(address(token), 1) == 1000);
    }

    function testRevert_UpdateFindersFeeMustBeSeller() public {
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        vm.warp(1 hours);

        vm.expectRevert("setCollectionOfferFindersFee msg sender must be seller");
        offers.setCollectionOfferFindersFee(address(token), 1, 1000);
    }

    function testRevert_UpdateFindersFeeMustBeValidBps() public {
        vm.startPrank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        vm.warp(1 hours);

        vm.expectRevert("setCollectionOfferFindersFee must be less than or equal to 10000 bps");
        offers.setCollectionOfferFindersFee(address(token), 1, 10001);

        vm.stopPrank();
    }

    /// ------------ CANCEL COLLECTION OFFER ------------ ///

    function test_CancelCollectionOffer() public {
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        vm.warp(1 hours);

        uint256 beforeSellerBalance = address(seller).balance;

        vm.prank(address(seller));
        offers.cancelCollectionOffer(address(token), 1);

        uint256 afterSellerBalance = address(seller).balance;
        require(afterSellerBalance - beforeSellerBalance == 1 ether);
    }

    function testRevert_CancelOfferMustBeSeller() public {
        vm.prank(address(seller));
        offers.createCollectionOffer{value: 1 ether}(address(token));

        vm.expectRevert("cancelCollectionOffer offer must be active & msg sender must be seller");
        offers.cancelCollectionOffer(address(token), 1);
    }

    /// ------------ FILL COLLECTION OFFER ------------ ///

    function test_FillCollectionOffer() public {
        loadOffers();

        vm.prank(address(buyer));
        offers.fillCollectionOffer(address(token), 0, 2 ether, address(finder));

        require(token.ownerOf(0) == address(seller2));
    }

    function testRevert_FillMinimumTooHigh() public {
        loadOffers();

        vm.prank(address(buyer));
        vm.expectRevert("fillCollectionOffer offer satisfying specified _minAmount not found");
        offers.fillCollectionOffer(address(token), 0, 5 ether, address(finder));
    }

    function testRevert_MustOwnCollectionToken() public {
        loadOffers();

        vm.expectRevert("fillCollectionOffer msg sender must own specified token");
        offers.fillCollectionOffer(address(token), 0, 2 ether, address(finder));
    }
}
