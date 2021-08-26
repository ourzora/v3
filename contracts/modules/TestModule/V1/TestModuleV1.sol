// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../../../interfaces/IModule.sol";

import "hardhat/console.sol";

contract TestModuleV1 is IModule {
    bytes32 internal constant TEST_MODULE_STORAGE_POSITION = keccak256("TestModule.V1");

    struct TestModuleStorage {
        uint256 magicNumber;
    }

    function storageSlot() external pure override returns (bytes32) {
        return TEST_MODULE_STORAGE_POSITION;
    }

    function testModuleStorage() internal pure returns (TestModuleStorage storage s) {
        bytes32 position = TEST_MODULE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function setMagicNumber(uint256, uint256 _num) external {
        TestModuleStorage storage s = testModuleStorage();
        s.magicNumber = _num;
    }

    function getMagicNumber(uint256) external view returns (uint256) {
        TestModuleStorage storage s = testModuleStorage();
        return s.magicNumber;
    }
}
