// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ZoraModuleManager} from "../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ZoraRegistrar} from "./utils/users/ZoraRegistrar.sol";
import {Zorb} from "./utils/users/Zorb.sol";

import {SimpleModule} from "./utils/modules/SimpleModule.sol";
import {VM} from "./utils/VM.sol";

/// @title ZoraModuleManagerTest
/// @notice Unit Tests for the ZORA Module Manager
contract ZoraModuleManagerTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;

    Zorb internal alice;
    Zorb internal bob;

    address[] internal batchModules;
    address internal module;

    function setUp() public {
        // Cheatcodes
        vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create users
        alice = new Zorb(address(ZMM));
        bob = new Zorb(address(ZMM));

        // Deploy mocks
        batchModules = [address(new SimpleModule()), address(new SimpleModule()), address(new SimpleModule())];
        module = batchModules[0];
    }

    /// ------------ APPROVE MODULE ------------ ///

    function test_SetApproval() public {
        registrar.registerModule(module);

        bob.setApprovalForModule(module, true);

        require(ZMM.isModuleApproved(address(bob), module));
    }

    function testFail_CannotApproveModuleNotRegistered() public {
        bob.setApprovalForModule(module, true);
    }

    /// ------------ APPROVE MODULE BATCH ------------ ///

    function test_SetBatchApproval() public {
        for (uint256 i = 0; i < 3; i++) {
            registrar.registerModule(batchModules[i]);
        }

        bob.setBatchApprovalForModules(batchModules, true);

        require(
            ZMM.isModuleApproved(address(bob), batchModules[0]) &&
                ZMM.isModuleApproved(address(bob), batchModules[1]) &&
                ZMM.isModuleApproved(address(bob), batchModules[2])
        );
    }

    /// ------------ REGISTER MODULE ------------ ///

    function test_RegisterModule() public {
        registrar.registerModule(module);
        require(ZMM.moduleRegistered(module));
    }

    function testRevert_ModuleAlreadyRegistered() public {
        registrar.registerModule(module);

        vm.expectRevert("ZMM::registerModule module already registered");
        registrar.registerModule(module);
    }

    /// ------------ SET REGISTRAR ------------ ///

    function test_SetRegistrar() public {
        registrar.setRegistrar(address(3));
        require(ZMM.registrar() == address(3));
    }

    function testRevert_CannotSetRegistrarToAddressZero() public {
        vm.expectRevert("ZMM::setRegistrar must set registrar to non-zero address");
        registrar.setRegistrar(address(0));
    }
}
