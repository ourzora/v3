// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraModuleApprovalsManager} from "../ZoraModuleApprovalsManager.sol";

/// @title Base Transfer Helper
/// @author tbtstl <t@zora.co>
/// @notice This contract provides shared utility for ZORA transfer helpers
contract BaseTransferHelper {
    ZoraModuleApprovalsManager immutable approvalsManager;

    /// @param _approvalsManager The ZORA Module Approvals Manager to use as a reference for transfer permissions
    constructor(address _approvalsManager) {
        require(_approvalsManager != address(0), "must set approvals manager to non-zero address");

        approvalsManager = ZoraModuleApprovalsManager(_approvalsManager);
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
        return approvalsManager.isModuleApproved(_user, msg.sender);
    }
}
