// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraProposalManager} from "./ZoraProposalManager.sol";
import {ZoraModuleApprovalsManager} from "./ZoraModuleApprovalsManager.sol";

contract BaseTransferHelper {
    address proposalManager;
    address approvalsManager;

    // Only allows the method to continue if the caller is an approved zora module
    modifier onlyRegisteredAndApprovedModule(address _from) {
        // Require the caller to have passed a zora proposal
        require(ZoraProposalManager(proposalManager).isPassedProposal(msg.sender), "only registered modules");

        // True if _from is a module (modules are automatically allowed to transfer)
        bool isFromModule = ZoraProposalManager(proposalManager).proposalImplementationToProposalID(_from) != 0;
        // True if _from has approvals for all
        bool hasApprovedAll = ZoraModuleApprovalsManager(approvalsManager).approvedForAll(_from);
        // True if _from has approved the msg.sender to spend
        bool hasApprovedModule = ZoraModuleApprovalsManager(approvalsManager).userApprovals(_from, msg.sender);

        require(isFromModule || hasApprovedAll || hasApprovedModule, "module has not been approved by user");

        _;
    }

    constructor(address _proposalManager, address _approvalsManager) {
        require(_proposalManager != address(0), "must set proposal manager to non-zero address");
        require(_approvalsManager != address(0), "must set approvals manager to non-zero address");

        proposalManager = _proposalManager;
        approvalsManager = _approvalsManager;
    }
}
