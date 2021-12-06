// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraProposalManager} from "./ZoraProposalManager.sol";

/// @title ZORA Module Proposal Manager
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to explicitly allow modules access to the ZORA transfer helpers on their behalf
contract ZoraModuleApprovalsManager {
    /// @notice The address of the proposal manager, manages allowed modules
    ZoraProposalManager public proposalManager;

    /// @notice Mapping of specific approvals for (module, user) pairs in the ZORA registry
    mapping(address => mapping(address => bool)) public userApprovals;

    event ModuleApprovalSet(address indexed user, address indexed module, bool approved);
    event AllModulesApprovalSet(address indexed user, bool approved);

    /// @param _proposalManager The address of the ZORA proposal manager
    constructor(address _proposalManager) {
        proposalManager = ZoraProposalManager(_proposalManager);
    }

    /// @notice Returns true if the user has approved a given module, false otherwise
    /// @param _user The user to check approvals for
    /// @param _module The module to check approvals for
    /// @return True if the module has been approved by the user, false otherwise
    function isModuleApproved(address _user, address _module) external view returns (bool) {
        return userApprovals[_user][_module];
    }

    /// @notice Allows a user to set the approval for a given module
    /// @param _moduleAddress The module to approve
    /// @param _approved A boolean, whether or not to approve a module
    function setApprovalForModule(address _moduleAddress, bool _approved) public {
        require(proposalManager.isPassedProposal(_moduleAddress), "ZMAM::module must be approved");

        userApprovals[msg.sender][_moduleAddress] = _approved;

        emit ModuleApprovalSet(msg.sender, _moduleAddress, _approved);
    }

    /// @notice Sets approvals for multiple modules at once
    /// @param _moduleAddresses The list of module addresses to set approvals for
    /// @param _approved A boolean, whether or not to approve the modules
    function setBatchApprovalForModules(address[] memory _moduleAddresses, bool _approved) public {
        for (uint256 i = 0; i < _moduleAddresses.length; i++) {
            setApprovalForModule(_moduleAddresses[i], _approved);
        }
    }
}
