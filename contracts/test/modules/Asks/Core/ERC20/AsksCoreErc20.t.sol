// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AsksCoreErc20} from "../../../../../modules/Asks/Core/ERC20/AsksCoreErc20.sol";
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

/// @title AsksCoreErc20Test
/// @notice Unit Tests for Asks Core ERC-20
contract AsksCoreErc20Test is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    AsksCoreErc20 internal asks;
    TestERC721 internal token;
    WETH internal weth;

    Zorb internal seller;
    Zorb internal operator;
    Zorb internal otherSeller;
    Zorb internal buyer;
    Zorb internal finder;
    Zorb internal sellerFundsRecipient;
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
        operator = new Zorb(address(ZMM));
        otherSeller = new Zorb(address(ZMM));
        buyer = new Zorb(address(ZMM));
        finder = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Asks Core ERC-20
        asks = new AsksCoreErc20(address(erc20TransferHelper), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

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

        // Buyer approve ERC20TransferHelper
        vm.prank(address(buyer));
        weth.approve(address(erc20TransferHelper), 50 ether);
    }

    /// ------------ CREATE ASK ------------ ///

    function testGas_CreateAsk() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));
    }

    function test_CreateAsk() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        (address askSeller, uint256 askPrice, address askCurrency) = asks.askForNFT(address(token), 0);

        require(askSeller == address(seller));
        require(askPrice == 1 ether);
        require(askCurrency == address(weth));
    }

    function test_CreateAskFromTokenOperator() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(operator), true);

        operator.setApprovalForModule(address(asks), true);

        vm.prank(address(operator));
        asks.createAsk(address(token), 0, 0.5 ether, address(weth));

        (address askSeller, uint256 askPrice, address currency) = asks.askForNFT(address(token), 0);

        require(askSeller == address(seller));
        require(askPrice == 0.5 ether);
        require(currency == address(weth));
    }

    function test_CreateAskAndOverridePrevious() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        (address askSeller, , ) = asks.askForNFT(address(token), 0);

        require(askSeller == address(seller));

        vm.prank(address(seller));
        token.safeTransferFrom(address(seller), address(otherSeller), 0);
        require(token.ownerOf(0) == address(otherSeller));

        otherSeller.setApprovalForModule(address(asks), true);

        vm.prank(address(otherSeller));
        token.setApprovalForAll(address(erc721TransferHelper), true);

        vm.prank(address(otherSeller));
        asks.createAsk(address(token), 0, 10 ether, address(weth));

        (address newAskSeller, uint256 askPrice, ) = asks.askForNFT(address(token), 0);

        require(newAskSeller == address(otherSeller));
        require(askPrice == 10 ether);
    }

    function test_CreateMaxAskPrice() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 2**96 - 1, address(weth));

        (, uint256 askPrice, ) = asks.askForNFT(address(token), 0);

        require(askPrice == 2**96 - 1);
    }

    function testRevert_MustBeOwnerOrOperator() public {
        vm.expectRevert("ONLY_TOKEN_OWNER_OR_OPERATOR");
        asks.createAsk(address(token), 0, 1 ether, address(weth));
    }

    function testRevert_MaxAskPrice() public {
        vm.prank(address(seller));
        vm.expectRevert("INVALID_ASK_PRICE");
        asks.createAsk(address(token), 0, 2**96, address(weth));
    }

    /// ------------ SET ASK PRICE ------------ ///

    function test_IncreaseAskPrice() public {
        vm.startPrank(address(seller));

        asks.createAsk(address(token), 0, 1 ether, address(weth));
        asks.setAskPrice(address(token), 0, 5 ether, address(weth));

        vm.stopPrank();

        (, uint256 askPrice, ) = asks.askForNFT(address(token), 0);
        require(askPrice == 5 ether);
    }

    function test_DecreaseAskPrice() public {
        vm.startPrank(address(seller));

        asks.createAsk(address(token), 0, 1 ether, address(weth));
        asks.setAskPrice(address(token), 0, 0.5 ether, address(weth));

        vm.stopPrank();

        (, uint256 askPrice, ) = asks.askForNFT(address(token), 0);
        require(askPrice == 0.5 ether);
    }

    function test_UpdateAskCurrency() public {
        vm.startPrank(address(seller));

        asks.createAsk(address(token), 0, 1 ether, address(weth));
        asks.setAskPrice(address(token), 0, 1 ether, address(0));

        vm.stopPrank();

        (, , address askCurrency) = asks.askForNFT(address(token), 0);
        require(askCurrency == address(0));
    }

    function testRevert_OnlySellerCanSetAskPrice() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.expectRevert("ONLY_SELLER");
        asks.setAskPrice(address(token), 0, 5 ether, address(weth));
    }

    function testRevert_CannotUpdateCanceledAsk() public {
        vm.startPrank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));
        asks.cancelAsk(address(token), 0);

        vm.expectRevert("ONLY_SELLER");
        asks.setAskPrice(address(token), 0, 5 ether, address(weth));
        vm.stopPrank();
    }

    function testRevert_CannotUpdateFilledAsk() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(address(token), 0, 1 ether, address(weth));

        vm.prank(address(seller));
        vm.expectRevert("ONLY_SELLER");
        asks.setAskPrice(address(token), 0, 5 ether, address(weth));
    }

    function testRevert_CannotUpdateInvalidPrice() public {
        vm.startPrank(address(seller));

        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.warp(1 minutes);

        vm.expectRevert("INVALID_ASK_PRICE");
        asks.setAskPrice(address(token), 0, 2**96, address(weth));

        vm.stopPrank();
    }

    /// ------------ CANCEL ASK ------------ ///

    function test_CancelAskSeller() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        (, uint256 beforeAskPrice, ) = asks.askForNFT(address(token), 0);
        require(beforeAskPrice == 1 ether);

        vm.prank(address(seller));
        asks.cancelAsk(address(token), 0);

        (, uint256 afterAskPrice, ) = asks.askForNFT(address(token), 0);
        require(afterAskPrice == 0);
    }

    function test_CancelAskOwner() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(seller));
        token.transferFrom(address(seller), address(otherSeller), 0);

        vm.prank(address(seller));
        asks.cancelAsk(address(token), 0);

        (address askSeller, uint256 askPrice, ) = asks.askForNFT(address(token), 0);

        require(askSeller == address(0));
        require(askPrice == 0);
    }

    function testRevert_MustBeSellerOrOwner() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.expectRevert("ONLY_SELLER_OR_TOKEN_OWNER");
        asks.cancelAsk(address(token), 0);
    }

    /// ------------ FILL ASK ------------ ///

    function test_FillAsk() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        asks.fillAsk(address(token), 0, 1 ether, address(weth));

        require(token.ownerOf(0) == address(buyer));
    }

    function testRevert_MustApproveModule() public {
        seller.setApprovalForModule(address(asks), false);

        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        vm.expectRevert("module has not been approved by user");
        asks.fillAsk(address(token), 0, 1 ether, address(weth));
    }

    function testRevert_MustApproveERC721TransferHelper() public {
        vm.prank(address(seller));
        token.setApprovalForAll(address(erc721TransferHelper), false);

        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        asks.fillAsk(address(token), 0, 1 ether, address(weth));
    }

    function testRevert_AskMustBeActiveToFill() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(address(token), 0, 1 ether, address(weth));

        vm.expectRevert("INACTIVE_ASK");
        asks.fillAsk{value: 1 ether}(address(token), 0, 1 ether, address(weth));
    }

    function testRevert_PriceMismatch() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        vm.expectRevert("MUST_MATCH_PRICE");
        asks.fillAsk(address(token), 0, 0.5 ether, address(weth));
    }

    function testRevert_CurrencyMismatch() public {
        vm.prank(address(seller));
        asks.createAsk(address(token), 0, 1 ether, address(weth));

        vm.prank(address(buyer));
        vm.expectRevert("MUST_MATCH_CURRENCY");
        asks.fillAsk(address(token), 0, 1 ether, address(0));
    }
}
