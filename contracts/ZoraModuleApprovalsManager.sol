// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {ZoraProposalManager} from "./ZoraProposalManager.sol";

contract ZoraModuleApprovalsManager {
    address public constant ALL_MODULES_FLAG = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

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

    function isModuleApproved(address _module, address _user) external view returns (bool) {
        if (!proposalManager.isPassedProposal(_module)) {
            return false; // returns 'false' after proposal is frozen
        }

        // either has approved all or this specific module
        return userApprovals[_user][ALL_MODULES_FLAG] || userApprovals[_user][_module];
    }

    function setApprovalForModule(address _moduleAddress, bool _approved) public {
        require(proposalManager.isPassedProposal(_moduleAddress), "ZMAM::module must be approved");

        userApprovals[msg.sender][_moduleAddress] = _approved;

        emit ModuleApprovalSet(msg.sender, _moduleAddress, _approved);
    }

    function setApprovalForAll(bool _approved) external {
        userApprovals[msg.sender][ALL_MODULES_FLAG] = _approved;

        emit AllModulesApprovalSet(msg.sender, _approved);
    }

    function setBatchApprovalForModules(address[] memory _moduleAddresses, bool _approved) external {
        for (uint256 i = 0; i < _moduleAddresses.length; i++) {
            setApprovalForModule(_moduleAddresses[i], _approved);
        }
    }
}
