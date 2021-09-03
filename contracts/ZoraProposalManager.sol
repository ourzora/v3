// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

contract ZoraProposalManager {
    using Counters for Counters.Counter;

    enum ProposalStatus {
        Pending,
        Passed,
        Failed
    }
    struct Proposal {
        address proposer;
        address implementationAddress;
        uint256 id;
        ProposalStatus status;
    }

    address public registrar;
    mapping(address => uint256) public proposalImplementationToProposalID;
    mapping(uint256 => Proposal) public proposalIDToProposal;
    Counters.Counter proposalCounter;

    modifier onlyRegistrar() {
        require(msg.sender == registrar, "onlyRegistrar");
        _;
    }

    constructor(address _registrarAddress) {
        require(_registrarAddress != address(0), "ZPM must set registrar to non-zero address");

        registrar = _registrarAddress;
    }

    function isPassedProposal(address _proposalImpl) public view returns (bool) {
        uint256 proposalID = proposalImplementationToProposalID[_proposalImpl];

        return proposalIDToProposal[proposalID].status == ProposalStatus.Passed;
    }

    function proposeModule(address _impl) public returns (uint256) {
        require(proposalImplementationToProposalID[_impl] == 0, "ZPM::proposeModule proposal already exists");
        require(_impl != address(0), "ZPM::proposeModule proposed contract cannot be zero address");

        proposalCounter.increment();
        uint256 proposalID = proposalCounter.current();
        Proposal memory proposal = Proposal({id: proposalID, proposer: msg.sender, implementationAddress: _impl, status: ProposalStatus.Pending});
        proposalIDToProposal[proposalID] = proposal;
        proposalImplementationToProposalID[_impl] = proposalID;

        // TODO: emit proposal event

        return proposalID;
    }

    function registerModule(uint256 _proposalID) public onlyRegistrar {
        Proposal storage proposal = proposalIDToProposal[_proposalID];

        require(proposal.implementationAddress != address(0), "ZPM::registerModule proposal does not exist");
        require(proposal.status == ProposalStatus.Pending, "ZPM::registerModule can only register pending proposals");

        proposal.status = ProposalStatus.Passed;

        // TODO: emit event
    }

    function cancelProposal(uint256 proposalID) public onlyRegistrar {
        require(proposalIDToProposal[proposalID].implementationAddress != address(0), "ZPM::cancelProposal proposal does not exist");
        require(proposalIDToProposal[proposalID].status == ProposalStatus.Pending, "ZPM::cancelProposal can only cancel pending proposals");

        Proposal storage proposal = proposalIDToProposal[proposalID];
        proposal.status = ProposalStatus.Failed;

        // TODO: emit event
    }

    function setRegistrar(address _registrarAddress) public onlyRegistrar {
        require(_registrarAddress != address(0), "ZPM::setRegistrar must set registrar to non-zero address");
        registrar = _registrarAddress;

        // TODO: emit event
    }
}
