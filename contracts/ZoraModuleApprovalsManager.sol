// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraProposalManager} from "./ZoraProposalManager.sol";

contract ZoraModuleApprovalsManager {
    // The address of the proposal manager, manages allowed modules
    ZoraProposalManager public proposalManager;

    // Map of users who approve all modules in the zora registry
    mapping(address => bool) public approvedForAll;

    // Map of specific approvals for modules and users in the zora registry
    // user address => module address => approved
    mapping(address => mapping(address => bool)) public userApprovals;

    constructor(address _proposalManager) {
        proposalManager = ZoraProposalManager(_proposalManager);
    }

    function isModuleApproved(address _module, address _user) external view returns (bool) {
        return approvedForAll[_user] || userApprovals[_user][_module];
    }

    function setApprovalForAllModules(bool _approved) public {
        approvedForAll[msg.sender] = _approved;

        // TODO: emit event
    }

    function setApprovalForModule(address _moduleAddress, bool _approved) public {
        require(proposalManager.isPassedProposal(_moduleAddress), "ZMAM::module must be approved");

        userApprovals[msg.sender][_moduleAddress] = _approved;

        // TODO: emit event
    }

    function setBatchApprovalForModules(address[] memory _moduleAddresses, bool _approved) public {
        for (uint256 i = 0; i < _moduleAddresses.length; i++) {
            setApprovalForModule(_moduleAddresses[i], _approved);
        }
    }
}
