// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ZoraModuleManager} from "../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ZoraRegistrar} from "../utils/users/ZoraRegistrar.sol";
import {Zorb} from "../utils/users/Zorb.sol";
import {ERC20TransferHelper} from "../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../transferHelpers/ERC721TransferHelper.sol";
import {ERC1155TransferHelper} from "../../transferHelpers/ERC1155TransferHelper.sol";

import {TransferModule} from "../utils/modules/TransferModule.sol";
import {TestERC721} from "../utils/tokens/TestERC721.sol";
import {VM} from "../utils//VM.sol";

/// @title ERC721TransferHelperTest
/// @notice Unit Tests for the ZORA ERC-721 Transfer Helper
contract ERC721TransferHelperTest is DSTest {
    VM internal vm;

    Zorb internal alice;
    TransferModule internal module;
    TestERC721 internal token;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;

    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    ERC1155TransferHelper internal erc1155TransferHelper;

    function setUp() public {
        // Cheatcodes
        vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
        erc721TransferHelper = new ERC721TransferHelper(address(ZMM));
        erc1155TransferHelper = new ERC1155TransferHelper(address(ZMM));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create user
        alice = new Zorb(address(ZMM));

        // Deploy mocks
        token = new TestERC721();
        module = new TransferModule(address(erc20TransferHelper), address(erc721TransferHelper), address(erc1155TransferHelper));
        registrar.registerModule(address(module));

        // Mint user token
        token.mint(address(alice), 0);
    }

    function test_ERC721Transfer() public {
        vm.startPrank(address(alice));

        // Approve ERC721TransferHelper as operator
        token.setApprovalForAll(address(erc721TransferHelper), true);
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Transfer token to module
        module.depositERC721(address(token), address(alice), 0);

        vm.stopPrank();

        require(token.ownerOf(0) == address(module));
    }

    function testRevert_UserMustApproveModule() public {
        vm.startPrank(address(alice));

        // Approve ERC721TransferHelper as operator
        token.setApprovalForAll(address(erc721TransferHelper), true);
        // Attempt token transfer without ZMM approval
        vm.expectRevert("module has not been approved by user");
        module.depositERC721(address(token), address(alice), 0);

        vm.stopPrank();
    }

    function testFail_UserMustApproveTransferHelper() public {
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);

        // Attempt token transfer without ERC721TransferHelper approval
        vm.prank(address(alice));
        module.depositERC721(address(token), address(alice), 0);
    }
}
