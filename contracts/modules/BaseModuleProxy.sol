// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../interfaces/IModule.sol";
import {LibVersionRegistry} from "../libraries/LibVersionRegistry.sol";
import {IModuleProxy} from "../interfaces/IModuleProxy.sol";

contract BaseModuleProxy is IModuleProxy {
    using LibVersionRegistry for LibVersionRegistry.RegistryStorage;

    // keccak256("core.registry")
    bytes32 constant VERSION_REGISTRY_STORAGE_POSITION = 0x3f3af226decc9238e7d7bff3a1fe46f3dba86ecfd6aa03cf2d9fb8c9ffddf485;

    constructor(address _registrarAddress) {
        _registryStorage().init(_registrarAddress, VERSION_REGISTRY_STORAGE_POSITION);
    }

    function proposeVersion(address _impl, bytes memory _calldata) public override returns (uint256) {
        return _registryStorage().proposeVersion(_impl, _calldata);
    }

    function registerVersion(uint256 _proposalId) public override returns (uint256) {
        return _registryStorage().registerVersion(_proposalId);
    }

    function cancelProposal(uint256 _proposalId) public override {
        return _registryStorage().cancelProposal(_proposalId);
    }

    function setRegistrar(address _registrarAddress) public override {
        return _registryStorage().setRegistrar(_registrarAddress);
    }

    function versionToImplementationAddress(uint256 _version) public view override returns (address) {
        return _registryStorage().versionToImplementationAddress[_version];
    }

    function implementationAddressToVersion(address _impl) public view override returns (uint256) {
        return _registryStorage().implementationAddressToVersion[_impl];
    }

    function proposal(uint256 _proposalId) public view returns (LibVersionRegistry.VersionProposal memory) {
        return _registryStorage().proposalIDToProposal[_proposalId];
    }

    function registrar() public view returns (address) {
        return _registryStorage().registrarAddress;
    }

    function _unpackVersionFromCallData() private pure returns (uint256) {
        require(msg.data.length >= 36, "BaseModuleProxy::_unpackVersionFromCallData msg data too short to have a version");
        return abi.decode(msg.data[4:36], (uint256));
    }

    function _registryStorage() private pure returns (LibVersionRegistry.RegistryStorage storage s) {
        bytes32 position = VERSION_REGISTRY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    fallback() external payable {
        LibVersionRegistry.RegistryStorage storage s = _registryStorage();
        uint256 version = _unpackVersionFromCallData();
        address implementation = s.versionToImplementationAddress[version];
        require(implementation != address(0), "provided version does not have implementation");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
