// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {OffersV1} from "../../../../modules/Offers/V1/OffersV1.sol";
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

/// @title OffersV1Test
/// @notice Unit Tests for Offers v1.0
contract OffersV1Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    OffersV1 internal offers;
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

        // Deploy Offers v1.0
        offers = new OffersV1(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(offers));

        // Set seller balance
        vm.deal(address(seller), 100 ether);

        // Mint buyer token
        token.mint(address(buyer), 0);

        // Seller swap 50 ETH <> 50 WETH
        vm.prank(address(seller));
        weth.deposit{value: 50 ether}();

        // Users approve Offers module
        seller.setApprovalForModule(address(offers), true);
        buyer.setApprovalForModule(address(offers), true);

        // Seller approve ERC20TransferHelper
        vm.prank(address(seller));
        weth.approve(address(erc20TransferHelper), 50 ether);

        // Buyer approve ERC721TransferHelper
        vm.prank(address(buyer));
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    /// ------------ CREATE NFT OFFER ------------ ///

    function testGas_CreateOffer() public {
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);
    }

    function test_CreateOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        (address offeror, , , ) = offers.offers(address(token), 0, 1);

        require(offeror == address(seller));
    }

    function testFail_CannotCreateOfferOnOwnNFT() public {
        vm.prank(address(buyer));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);
    }

    function testFail_CannotCreateOfferWithoutAttachingFunds() public {
        vm.prank(address(seller));
        offers.createNFTOffer(address(token), 0, address(0), 1 ether, 1000);
    }

    /// ------------ UPDATE NFT OFFER ------------ ///

    function test_IncreaseOffer() public {
        vm.startPrank(address(seller));

        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);
        offers.setNFTOfferAmount{value: 1 ether}(address(token), 0, 1, 2 ether);

        vm.stopPrank();

        (, , , uint256 amount) = offers.offers(address(token), 0, 1);

        require(amount == 2 ether);
    }

    function test_DecreaseOffer() public {
        vm.startPrank(address(seller));

        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);
        offers.setNFTOfferAmount(address(token), 0, 1, 0.5 ether);

        vm.stopPrank();

        (, , , uint256 amount) = offers.offers(address(token), 0, 1);

        require(amount == 0.5 ether);
    }

    function testRevert_OnlySellerCanUpdateOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.expectRevert("setNFTOfferAmount must be seller");
        offers.setNFTOfferAmount(address(token), 0, 1, 0.5 ether);
    }

    function testRevert_CannotIncreaseOfferWithoutAttachingFunds() public {
        vm.startPrank(address(seller));

        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);
        vm.expectRevert("_handleIncomingTransfer msg value less than expected amount");
        offers.setNFTOfferAmount(address(token), 0, 1, 2 ether);

        vm.stopPrank();
    }

    function testRevert_CannotUpdateInactiveOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.prank(address(buyer));
        offers.fillNFTOffer(address(token), 0, 1, address(0), 1 ether, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("setNFTOfferAmount must be seller");
        offers.setNFTOfferAmount(address(token), 0, 1, 0.5 ether);
    }

    /// ------------ CANCEL NFT OFFER ------------ ///

    function test_CancelNFTOffer() public {
        vm.startPrank(address(seller));

        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        (, , , uint256 beforeAmount) = offers.offers(address(token), 0, 1);
        require(beforeAmount == 1 ether);

        offers.cancelNFTOffer(address(token), 0, 1);

        (, , , uint256 afterAmount) = offers.offers(address(token), 0, 1);
        require(afterAmount == 0);

        vm.stopPrank();
    }

    function testRevert_CannotCancelInactiveOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.prank(address(buyer));
        offers.fillNFTOffer(address(token), 0, 1, address(0), 1 ether, address(finder));

        vm.prank(address(seller));
        vm.expectRevert("cancelNFTOffer must be seller");
        offers.cancelNFTOffer(address(token), 0, 1);
    }

    function testRevert_OnlySellerCanCancelOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.expectRevert("cancelNFTOffer must be seller");
        offers.cancelNFTOffer(address(token), 0, 1);
    }

    /// ------------ FILL NFT OFFER ------------ ///

    function test_FillNFTOffer() public {
        vm.prank(address(seller));
        offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        address beforeTokenOwner = token.ownerOf(0);

        vm.prank(address(buyer));
        offers.fillNFTOffer(address(token), 0, 1, address(0), 1 ether, address(finder));

        address afterTokenOwner = token.ownerOf(0);

        require(beforeTokenOwner == address(buyer) && afterTokenOwner == address(seller));
    }

    function testRevert_OnlyTokenHolderCanFillOffer() public {
        vm.prank(address(seller));
        uint256 id = offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.expectRevert("fillNFTOffer must be token owner");
        offers.fillNFTOffer(address(token), 0, id, address(0), 1 ether, address(finder));
    }

    function testRevert_CannotFillInactiveOffer() public {
        vm.prank(address(seller));
        uint256 id = offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.prank(address(buyer));
        offers.fillNFTOffer(address(token), 0, id, address(0), 1 ether, address(finder));

        vm.prank(address(buyer));
        vm.expectRevert("fillNFTOffer must be active offer");
        offers.fillNFTOffer(address(token), 0, id, address(0), 1 ether, address(finder));
    }

    function testRevert_AcceptCurrencyMustMatchOffer() public {
        vm.prank(address(seller));
        uint256 id = offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.prank(address(buyer));
        vm.expectRevert("fillNFTOffer _currency must match offer currency");
        offers.fillNFTOffer(address(token), 0, id, address(weth), 1 ether, address(finder));
    }

    function testRevert_AcceptAmountMustMatchOffer() public {
        vm.prank(address(seller));
        uint256 id = offers.createNFTOffer{value: 1 ether}(address(token), 0, address(0), 1 ether, 1000);

        vm.prank(address(buyer));
        vm.expectRevert("fillNFTOffer _amount must match offer amount");
        offers.fillNFTOffer(address(token), 0, id, address(0), 0.5 ether, address(finder));
    }
}
