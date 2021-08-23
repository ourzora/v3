// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../interfaces/IModule.sol";
import {LibVersionRegistry} from "../libraries/LibVersionRegistry.sol";
import {IModuleProxy} from "../interfaces/IModuleProxy.sol";

contract BaseModuleProxy is IModuleProxy {
    function registerVersion(address _impl, bytes memory _calldata) public override {
        uint256 version = IModule(_impl).version();
        LibVersionRegistry.addVersion(version, _impl, _calldata);
    }

    function versionToImplementationAddress(uint256 _version) public view override returns (address) {
        LibVersionRegistry.RegistryStorage storage s = LibVersionRegistry.registryStorage();

        return s.versionToImplementationAddress[_version];
    }

    function implementationAddressToVersion(address _impl) public view override returns (uint256) {
        LibVersionRegistry.RegistryStorage storage s = LibVersionRegistry.registryStorage();

        return s.implementationAddressToVersion[_impl];
    }

    function _unpackVersionFromCallData() private pure returns (uint256) {
        require(msg.data.length >= 36, "BaseModuleProxy::_unpackVersionFromCallData msg data too short to have a version");
        return abi.decode(msg.data[4:36], (uint256));
    }

    fallback() external payable {
        LibVersionRegistry.RegistryStorage storage s = LibVersionRegistry.registryStorage();
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
