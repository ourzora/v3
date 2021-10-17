// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraModuleApprovalsManager} from "../ZoraModuleApprovalsManager.sol";

/// @title Base Transfer Helper
/// @author tbtstl <t@zora.co>
/// @notice This contract provides shared utility for ZORA transfer helpers
contract BaseTransferHelper {
    ZoraModuleApprovalsManager approvalsManager;

    /// @param _approvalsManager The ZORA Module Approvals Manager to use as a reference for transfer permissions
    constructor(address _approvalsManager) {
        require(_approvalsManager != address(0), "must set approvals manager to non-zero address");

        approvalsManager = ZoraModuleApprovalsManager(_approvalsManager);
    }

    // Only allows the method to continue if the caller is an approved zora module
    modifier onlyApprovedModule(address _from) {
        require(approvalsManager.isModuleApproved(_from, msg.sender), "module has not been approved by user");

        _;
    }
}
