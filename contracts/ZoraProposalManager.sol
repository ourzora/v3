// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

/// @title ZORA Module Proposal Manager
/// @author tbtstl <t@zora.co>
/// @notice This contract accepts proposals and registers new modules, granting them access to the ZORA Module Approval Manager
contract ZoraProposalManager {
    enum ProposalStatus {
        Nonexistent,
        Pending,
        Passed,
        Failed
    }
    /// @notice A Proposal object that tracks a proposal and its status
    /// @member proposer The address that created the proposal
    /// @member status The status of the proposal (see ProposalStatus)
    struct Proposal {
        address proposer;
        ProposalStatus status;
    }

    /// @notice The registrar address that can register, or cancel
    address public registrar;
    /// @notice A mapping of module addresses to proposals
    mapping(address => Proposal) public proposedModuleToProposal;

    event ModuleProposed(address indexed contractAddress, address indexed proposer);
    event ModuleRegistered(address indexed contractAddress);
    event ModuleCanceled(address indexed contractAddress);
    event RegistrarChanged(address indexed newRegistrar);

    error OnlyRegistrar();
    error SetRegistrarToNonZeroAddress();
    error ProposalAlreadyExists();
    error ProposedContractCannotBeZeroAddress();
    error CanOnlyRegisterPendingProposals();
    error CanOnlyCancelPendingProposals();

    modifier onlyRegistrar() {
        if (msg.sender != registrar) {
            revert OnlyRegistrar();
        }
        _;
    }

    /// @param _registrarAddress The initial registrar for the manager
    constructor(address _registrarAddress) {
        if (_registrarAddress == address(0)) {
            revert SetRegistrarToNonZeroAddress();
        }

        registrar = _registrarAddress;
    }

    /// @notice Returns true if the module has been registered
    /// @param _proposalImpl The address of the proposed module
    /// @return True if the module has been registered, false otherwise
    function isPassedProposal(address _proposalImpl) public view returns (bool) {
        return proposedModuleToProposal[_proposalImpl].status == ProposalStatus.Passed;
    }

    /// @notice Creates a new proposal for a module
    /// @param _impl The address of the deployed module being proposed
    function proposeModule(address _impl) public {
        if (proposedModuleToProposal[_impl].proposer != address(0)) {
            revert ProposalAlreadyExists();
        }
        if (_impl == address(0)) {
            revert ProposedContractCannotBeZeroAddress();
        }

        Proposal memory proposal = Proposal({proposer: msg.sender, status: ProposalStatus.Pending});
        proposedModuleToProposal[_impl] = proposal;

        emit ModuleProposed(_impl, msg.sender);
    }

    /// @notice Registers a proposed module
    /// @param _proposalAddress The address of the proposed module
    function registerModule(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        if (proposal.status != ProposalStatus.Pending) {
            revert CanOnlyRegisterPendingProposals();
        }

        proposal.status = ProposalStatus.Passed;

        emit ModuleRegistered(_proposalAddress);
    }

    /// @notice Cancels a proposed module
    /// @param _proposalAddress The address of the proposed module
    function cancelProposal(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        if (proposal.status != ProposalStatus.Pending) {
            revert CanOnlyCancelPendingProposals();
        }

        proposal.status = ProposalStatus.Failed;

        emit ModuleCanceled(_proposalAddress);
    }

    /// @notice Sets the registrar for this manager
    /// @param _registrarAddress the address of the new registrar
    function setRegistrar(address _registrarAddress) public onlyRegistrar {
        if (_registrarAddress == address(0)) {
            revert SetRegistrarToNonZeroAddress();
        }
        registrar = _registrarAddress;

        emit RegistrarChanged(_registrarAddress);
    }
}
