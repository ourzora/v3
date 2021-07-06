// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

/**
 * @title IModule
 * @author tbtstl
 * @notice IModule provides the base methods required to register a module within Zora
 */
interface IModule {
    function version() external pure returns (uint256);
}
