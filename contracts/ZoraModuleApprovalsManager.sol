// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraProposalManager} from "./ZoraProposalManager.sol";

contract ZoraModuleApprovalsManager {
    // The address of the proposal manager, manages allowed modules
    ZoraProposalManager public proposalManager;

    // Map of specific approvals for modules and users in the zora registry
    // user address => module address => approved
    mapping(address => mapping(address => bool)) public userApprovals;

    event ModuleApprovalSet(address indexed user, address indexed module, bool approved);

    event AllModulesApprovalSet(address indexed user, bool approved);

    constructor(address _proposalManager) {
        proposalManager = ZoraProposalManager(_proposalManager);
    }

    function isModuleApproved(address _user, address _module) external view returns (bool) {
        return userApprovals[_user][_module];
    }

    function setApprovalForModule(address _moduleAddress, bool _approved) public {
        require(proposalManager.isPassedProposal(_moduleAddress), "ZMAM::module must be approved");

        userApprovals[msg.sender][_moduleAddress] = _approved;

        emit ModuleApprovalSet(msg.sender, _moduleAddress, _approved);
    }

    function setBatchApprovalForModules(address[] memory _moduleAddresses, bool _approved) public {
        for (uint256 i = 0; i < _moduleAddresses.length; i++) {
            setApprovalForModule(_moduleAddresses[i], _approved);
        }
    }
}
