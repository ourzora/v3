// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

contract ZoraProposalManager {
    enum ProposalStatus {
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

        // TODO: emit proposal event
    }

    function registerModule(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.proposer != address(0), "ZPM::registerModule proposal does not exist");
        require(proposal.status == ProposalStatus.Pending, "ZPM::registerModule can only register pending proposals");

        proposal.status = ProposalStatus.Passed;

        // TODO: emit event
    }

    function cancelProposal(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.proposer != address(0), "ZPM::cancelProposal proposal does not exist");
        require(proposal.status == ProposalStatus.Pending, "ZPM::cancelProposal can only cancel pending proposals");

        proposal.status = ProposalStatus.Failed;

        // TODO: emit event
    }

    function freezeProposal(address _proposalAddress) public onlyRegistrar {
        Proposal storage proposal = proposedModuleToProposal[_proposalAddress];

        require(proposal.proposer != address(0), "ZPM::freezeProposal proposal does not exist");
        require(proposal.status == ProposalStatus.Passed, "ZPM::freezeProposal can only freeze passed proposals");

        proposal.status = ProposalStatus.Frozen;

        // TODO: emit event
    }

    function setRegistrar(address _registrarAddress) public onlyRegistrar {
        require(_registrarAddress != address(0), "ZPM::setRegistrar must set registrar to non-zero address");
        registrar = _registrarAddress;

        // TODO: emit event
    }
}
