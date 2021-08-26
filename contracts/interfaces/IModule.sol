// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

/**
 * @title IModule
 * @author tbtstl
 * @notice IModule provides the base methods required to register a module within Zora
 */
interface IModule {
    // Return the storage slot to be reserved for this module
    function storageSlot() external pure returns (bytes32);

    function setVersion(uint256 _version) external;
}
