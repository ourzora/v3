// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraModuleManager} from "../ZoraModuleManager.sol";

/// @title Base Transfer Helper
/// @author tbtstl <t@zora.co>
/// @notice This contract provides shared utility for ZORA transfer helpers
contract BaseTransferHelper {
    /// @notice The ZORA Module Manager
    ZoraModuleManager public immutable ZMM;

    /// @param _moduleManager The ZORA Module Manager referred to for transfer permissions
    constructor(address _moduleManager) {
        require(_moduleManager != address(0), "must set module manager to non-zero address");

        ZMM = ZoraModuleManager(_moduleManager);
    }

    /// @notice Ensures a user has approved the module they're calling
    /// @param _user The address of the user
    modifier onlyApprovedModule(address _user) {
        require(isModuleApproved(_user), "module has not been approved by user");
        _;
    }

    /// @notice If a user has approved the module they're calling
    /// @param _user The address of the user
    function isModuleApproved(address _user) public view returns (bool) {
        return ZMM.isModuleApproved(_user, msg.sender);
    }
}
