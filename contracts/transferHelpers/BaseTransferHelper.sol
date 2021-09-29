// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraModuleApprovalsManager} from "../ZoraModuleApprovalsManager.sol";

contract BaseTransferHelper {
    ZoraModuleApprovalsManager approvalsManager;

    constructor(address _approvalsManager) {
        require(_approvalsManager != address(0), "must set approvals manager to non-zero address");

        approvalsManager = ZoraModuleApprovalsManager(_approvalsManager);
    }

    // Only allows the method to continue if the caller is an approved zora module
    modifier onlyApprovedModule(address _from) {
        require(approvalsManager.isModuleApproved(msg.sender, _from), "module has not been approved by user");

        _;
    }
}
