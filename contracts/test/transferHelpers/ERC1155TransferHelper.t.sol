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
import {TestERC1155} from "../utils/tokens/TestERC1155.sol";
import {VM} from "../utils//VM.sol";

/// @title ERC1155TransferHelperTest
/// @notice Unit Tests for the ZORA ERC-1155 Transfer Helper
contract ERC1155TransferHelperTest is DSTest {
    VM internal vm;

    Zorb internal alice;
    TransferModule internal module;
    TestERC1155 internal token;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;

    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    ERC1155TransferHelper internal erc1155TransferHelper;

    uint256[] internal batchIds;
    uint256[] internal batchAmounts;

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
        token = new TestERC1155();
        module = new TransferModule(address(erc20TransferHelper), address(erc721TransferHelper), address(erc1155TransferHelper));
        registrar.registerModule(address(module));

        // Mint user ERC1155 tokens
        batchIds = [1, 2];
        batchAmounts = [100, 100];
        token.mint(address(alice), 0, 1);
        token.mintBatch(address(alice), batchIds, batchAmounts);
    }

    function test_ERC1155TransferSingle() public {
        vm.startPrank(address(alice));

        // Approve ERC1155TransferHelper as operator
        token.setApprovalForAll(address(erc1155TransferHelper), true);
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Transfer token to module
        module.safeDepositERC1155(address(token), address(alice), 0, 1);

        vm.stopPrank();

        require(token.balanceOf(address(module), 0) == 1);
    }

    function test_ERC1155TransferBatch() public {
        vm.startPrank(address(alice));

        // Approve ERC1155TransferHelper as operator
        token.setApprovalForAll(address(erc1155TransferHelper), true);
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Transfer batch tokens to module
        module.safeBatchDepositERC1155(address(token), address(alice), batchIds, batchAmounts);

        vm.stopPrank();

        require(token.balanceOf(address(module), batchIds[0]) == batchAmounts[0]);
        require(token.balanceOf(address(module), batchIds[1]) == batchAmounts[1]);
    }

    function testRevert_UserMustApproveModuleToTransferSingle() public {
        vm.startPrank(address(alice));

        // Approve ERC1155TransferHelper as operator
        token.setApprovalForAll(address(erc1155TransferHelper), true);
        // Attempt token transfer without ZMM approval
        vm.expectRevert("module has not been approved by user");
        module.safeDepositERC1155(address(token), address(alice), 0, 1);

        vm.stopPrank();
    }

    function testRevert_UserMustApproveModuleToTransferBatch() public {
        vm.startPrank(address(alice));

        // Approve ERC1155TransferHelper as operator in TestERC1155
        token.setApprovalForAll(address(erc1155TransferHelper), true);
        // Attempt batch token transfer without ZMM approval
        vm.expectRevert("module has not been approved by user");
        module.safeBatchDepositERC1155(address(token), address(alice), batchIds, batchAmounts);

        vm.stopPrank();
    }

    function testFail_UserMustApproveTransferHelperToTransferSingle() public {
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Attempt token transfer without ERC1155TransferHelper approval
        vm.prank(address(alice));
        module.safeDepositERC1155(address(token), address(alice), 0, 1);
    }

    function testFail_UserMustApproveTransferHelperToTransferBatch() public {
        // Approve module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Attempt batch token transfer without ERC1155TransferHelper approval
        vm.prank(address(alice));
        module.safeBatchDepositERC1155(address(token), address(alice), batchIds, batchAmounts);
    }
}
