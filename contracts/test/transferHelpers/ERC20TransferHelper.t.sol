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
import {WETH} from "../utils/tokens/WETH.sol";
import {VM} from "../utils//VM.sol";

/// @title ERC20TransferHelperTest
/// @notice Unit Tests for the ZORA ERC-20 Transfer Helper
contract ERC20TransferHelperTest is DSTest {
    VM internal vm;

    Zorb internal alice;
    TransferModule internal module;
    WETH internal weth;

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
        weth = new WETH();
        module = new TransferModule(address(erc20TransferHelper), address(erc721TransferHelper), address(erc1155TransferHelper));
        registrar.registerModule(address(module));

        // Set user balance
        vm.deal(address(alice), 100 ether);

        // User swap 1 ETH <> 1 WETH
        vm.prank(address(alice));
        weth.deposit{value: 1 ether}();
    }

    function test_ERC20Transfer() public {
        vm.startPrank(address(alice));

        // Approve ERC20TransferHelper for up to 1 WETH
        weth.approve(address(erc20TransferHelper), 1 ether);
        // Approve test module in ZMM
        alice.setApprovalForModule(address(module), true);
        // Transfer 0.5 WETH
        module.depositERC20(address(weth), address(alice), 0.5 ether);

        vm.stopPrank();

        require(weth.balanceOf(address(alice)) == 0.5 ether, "alice");
        require(weth.balanceOf(address(module)) == 0.5 ether, "module");
    }

    function testRevert_UserMustApproveModule() public {
        vm.startPrank(address(alice));

        // Approve ERC20TransferHelper for up to 1 WETH
        weth.approve(address(erc20TransferHelper), 0.5 ether);
        // Attempt 0.5 WETH transfer wihout ZMM approval
        vm.expectRevert("module has not been approved by user");
        module.depositERC20(address(weth), address(alice), 0.5 ether);

        vm.stopPrank();
    }

    function testFail_UserMustApproveTransferHelper() public {
        // Approve test module in ZMM
        alice.setApprovalForModule(address(module), true);

        // Attempt 0.5 WETH transfer without ERC20TransferHelper approval
        vm.prank(address(alice));
        module.depositERC20(address(weth), address(alice), 0.5 ether);
    }
}
