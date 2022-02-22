// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ZoraProtocolFeeSettings} from "../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ZoraModuleManager} from "../../ZoraModuleManager.sol";
import {ZoraRegistrar} from "../utils/users/ZoraRegistrar.sol";
import {Zorb} from "../utils/users/Zorb.sol";

import {SimpleModule} from "../utils/modules/SimpleModule.sol";
import {TestERC721} from "../utils/tokens/TestERC721.sol";
import {VM} from "../utils/VM.sol";

/// @title ZoraProtocolFeeSettingsTest
/// @notice Unit Tests for ZORA Protocol Fee Settings
contract ZoraProtocolFeeSettingsTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    Zorb internal feeRecipient;

    SimpleModule internal module;
    TestERC721 internal token;

    function setUp() public {
        // Cheatcodes
        vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Deploy V3
        registrar = new ZoraRegistrar();
        vm.prank(address(registrar));
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        feeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        token = new TestERC721();
        module = new SimpleModule();
    }

    /// ------------ INIT ------------ ///

    function init() public {
        vm.prank(address(registrar));
        ZPFS.init(address(ZMM), address(token));
    }

    function test_Init() public {
        init();

        require(ZPFS.minter() == address(ZMM));
        require(ZPFS.metadata() == address(token));
    }

    function testRevert_InitOnlyOwner() public {
        vm.expectRevert("init only owner");
        ZPFS.init(address(ZMM), address(token));
    }

    function testRevert_AlreadyInitialized() public {
        init();

        vm.prank(address(registrar));
        vm.expectRevert("init already initialized");
        ZPFS.init(address(ZMM), address(token));
    }

    /// ------------ SET OWNER ------------ ///

    function test_SetOwner() public {
        init();

        vm.prank(address(registrar));
        ZPFS.setOwner(address(this));

        require(ZPFS.owner() == address(this));
    }

    function testRevert_SetOwnerOnlyOwner() public {
        init();

        vm.expectRevert("setOwner onlyOwner");
        ZPFS.setOwner(address(this));
    }

    /// ------------ SET METADATA ------------ ///

    function test_SetMetadata() public {
        init();

        vm.prank(address(registrar));
        ZPFS.setMetadata(address(1));

        require(ZPFS.metadata() == address(1));
    }

    function testRevert_SetMetadataOnlyOwner() public {
        init();

        vm.expectRevert("setMetadata onlyOwner");
        ZPFS.setMetadata(address(1));
    }

    /// ------------ MINT ------------ ///

    function mint() public {
        vm.prank(address(ZMM));
        ZPFS.mint(address(registrar), address(module));
    }

    function test_MintToken() public {
        init();
        mint();

        uint256 tokenId = ZPFS.moduleToTokenId(address(module));
        require(ZPFS.ownerOf(tokenId) == address(registrar));
    }

    function testRevert_OnlyMinter() public {
        init();

        vm.expectRevert("mint onlyMinter");
        ZPFS.mint(address(registrar), address(module));
    }

    /// ------------ SET FEE PARAMS ------------ ///

    function test_SetFeeParams() public {
        init();
        mint();

        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(module), address(feeRecipient), 1);

        (uint16 feeBps, address receiver) = ZPFS.moduleFeeSetting(address(module));

        require(feeBps == 1);
        require(receiver == address(feeRecipient));
    }

    function test_ResetParamsToZero() public {
        init();
        mint();

        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(module), address(feeRecipient), 0);

        (uint16 feeBps, address receiver) = ZPFS.moduleFeeSetting(address(module));

        require(feeBps == 0);
        require(receiver == address(feeRecipient));
    }

    function testRevert_SetParamsOnlyOwner() public {
        init();
        mint();

        vm.expectRevert("onlyModuleOwner");
        ZPFS.setFeeParams(address(module), address(feeRecipient), 0);
    }

    function testRevert_SetParamsMustBeLessThanHundred() public {
        init();
        mint();

        vm.prank(address(registrar));
        vm.expectRevert("setFeeParams must set fee <= 100%");
        ZPFS.setFeeParams(address(module), address(feeRecipient), 10001);
    }

    function testRevert_SetParamsFeeRecipientMustBeNonZero() public {
        init();
        mint();

        vm.prank(address(registrar));
        vm.expectRevert("setFeeParams fee recipient cannot be 0 address if fee is greater than 0");
        ZPFS.setFeeParams(address(module), address(0), 1);
    }
}
