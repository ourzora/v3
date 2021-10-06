// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

contract ZoraProposalManager {
    enum ProposalStatus {
        Nonexistent,
        Pending,
        Passed,
        Failed,
        Frozen
    }
    struct Proposal {
        address proposer;
        ProposalStatus status;
    }

    address public registrar;
    mapping(address => Proposal) public proposedModuleToProposal;

    event ModuleProposed(address indexed contractAddress, address indexed proposer);

    event ModuleRegistered(address indexed contractAddress);

    event ModuleCanceled(address indexed contractAddress);

    event ModuleFrozen(address indexed contractAddress);

    event RegistrarChanged(address indexed newRegistrar);

    modifier onlyRegistrar() {
        require(msg.sender == registrar, "ZPM::onlyRegistrar must be registrar");
        _;
    }

    constructor(address _registrarAddress) {
        require(_registrarAddress != address(0), "ZPM::must set registrar to non-zero address");

        registrar = _registrarAddress;
    }

    function isPassedProposal(address _proposalImpl) public view returns (bool) {
        return proposedModuleToProposal[_proposalImpl].status == ProposalStatus.Passed;
    }

    function proposeModule(address _impl) public {
        require(proposedModuleToProposal[_impl].proposer == address(0), "ZPM::proposeModule proposal already exists");
        require(_impl != address(0), "ZPM::proposeModule proposed contract cannot be zero address");

        Proposal memory proposal = Proposal({proposer: msg.sender, status: ProposalStatus.Pending});
        proposedModuleToProposal[_impl] = proposal;

        emit ModuleProposed(_impl, msg.sender);
    }

    function registerModule(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.status != ProposalStatus.Nonexistent, "ZPM::registerModule proposal does not exist");
        require(proposal.status == ProposalStatus.Pending, "ZPM::registerModule can only register pending proposals");

        proposal.status = ProposalStatus.Passed;

        emit ModuleRegistered(_proposalAddress);
    }

    function cancelProposal(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.status != ProposalStatus.Nonexistent, "ZPM::cancelProposal proposal does not exist");
        require(proposal.status == ProposalStatus.Pending, "ZPM::cancelProposal can only cancel pending proposals");

        proposal.status = ProposalStatus.Failed;

        emit ModuleCanceled(_proposalAddress);
    }

    function freezeProposal(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.status != ProposalStatus.Nonexistent, "ZPM::freezeProposal proposal does not exist");
        require(proposal.status == ProposalStatus.Passed, "ZPM::freezeProposal can only freeze passed proposals");

        proposal.status = ProposalStatus.Frozen;

        emit ModuleFrozen(_proposalAddress);
    }

    function setRegistrar(address _registrarAddress) public onlyRegistrar {
        require(_registrarAddress != address(0), "ZPM::setRegistrar must set registrar to non-zero address");
        registrar = _registrarAddress;

        emit RegistrarChanged(_registrarAddress);
    }
}
