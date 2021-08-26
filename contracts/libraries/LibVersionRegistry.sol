// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IModule} from "../interfaces/IModule.sol";

library LibVersionRegistry {
    using Counters for Counters.Counter;

    enum ProposalStatus {
        Pending,
        Passed,
        Failed
    }

    struct VersionProposal {
        address proposer;
        address implementationAddress;
        bytes initCallData;
        ProposalStatus status;
    }

    struct RegistryStorage {
        address registrarAddress;
        mapping(uint256 => VersionProposal) proposalIDToProposal;
        mapping(address => uint256) proposalImplementationToProposalID;
        mapping(uint256 => address) versionToImplementationAddress;
        mapping(address => uint256) implementationAddressToVersion;
        mapping(bytes32 => bool) reservedStorageSlots;
        Counters.Counter proposalCounter;
        Counters.Counter versionCounter;
        bool initialized;
    }

    function init(
        RegistryStorage storage _self,
        address _registrarAddress,
        bytes32 _reservedStorage
    ) internal {
        require(_self.initialized != true, "LibVersionRegistry already initialized");

        _self.registrarAddress = _registrarAddress;
        _self.reservedStorageSlots[_reservedStorage] = true;
        _self.initialized = true;
    }

    function proposeVersion(
        RegistryStorage storage _self,
        address _impl,
        bytes memory _initCallData
    ) internal returns (uint256) {
        require(
            _self.implementationAddressToVersion[_impl] == 0 && _self.proposalImplementationToProposalID[_impl] == 0,
            "LibVersionRegistry::proposeVersion implementation address already in use"
        );
        require(_impl != address(0), "LibVersionRegistry::proposeVersion cannot propose zero address implementation");

        _self.proposalCounter.increment();
        uint256 proposalID = _self.proposalCounter.current();
        _self.proposalIDToProposal[proposalID] = VersionProposal({
            proposer: msg.sender,
            implementationAddress: _impl,
            initCallData: _initCallData,
            status: ProposalStatus.Pending
        });
        _self.proposalImplementationToProposalID[_impl] = proposalID;

        return proposalID;
    }

    function registerVersion(RegistryStorage storage _self, uint256 _proposalId) internal returns (uint256) {
        require(msg.sender == _self.registrarAddress, "LibVersionRegistry::registerVersion only callable by registrar");
        require(_self.proposalIDToProposal[_proposalId].implementationAddress != address(0), "LibVersionRegistry::registerVersion nonexistant proposal");
        require(_self.proposalIDToProposal[_proposalId].status == ProposalStatus.Pending, "LibVersionRegistry::registerVersion proposal must be pending");

        VersionProposal memory proposal = _self.proposalIDToProposal[_proposalId];
        bytes32 storageSlot = IModule(proposal.implementationAddress).storageSlot();

        require(
            _self.implementationAddressToVersion[proposal.implementationAddress] == 0,
            "LibVersionRegistry::registerVersion implementation address already in use"
        );
        require(_self.reservedStorageSlots[storageSlot] == false, "LibVersionRegistry::registerVersion storage slot already allocated");

        if (proposal.initCallData.length != 0) {
            (bool success, ) = proposal.implementationAddress.delegatecall(proposal.initCallData);
            require(success, string(abi.encodePacked("LibVersionRegistry::registerVersion _impl call failed")));
        }

        _self.versionCounter.increment();
        uint256 version = _self.versionCounter.current();
        _self.implementationAddressToVersion[proposal.implementationAddress] = version;
        _self.versionToImplementationAddress[version] = proposal.implementationAddress;
        _self.reservedStorageSlots[storageSlot] = true;
        _self.proposalIDToProposal[_proposalId].status = ProposalStatus.Passed;

        return version;
    }

    function cancelProposal(RegistryStorage storage _self, uint256 _proposalID) internal {
        require(msg.sender == _self.registrarAddress, "LibVersionRegistry::cancelProposal only callable by registrar");
        require(_self.proposalIDToProposal[_proposalID].implementationAddress != address(0), "LibVersionRegistry::cancelProposal proposal does not exist");
        _self.proposalIDToProposal[_proposalID].status = ProposalStatus.Failed;
    }

    function setRegistrar(RegistryStorage storage _self, address _registrarAddress) internal {
        require(msg.sender == _self.registrarAddress, "LibVersionRegistry::setRegistrar only callable by registrar");

        _self.registrarAddress = _registrarAddress;
    }
}
