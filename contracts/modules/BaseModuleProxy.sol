// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../interfaces/IModule.sol";
import {LibVersionRegistry} from "../libraries/LibVersionRegistry.sol";
import {IModuleProxy} from "../interfaces/IModuleProxy.sol";

contract BaseModuleProxy is IModuleProxy {
    function registerVersion(address _impl) public override {
        uint256 version = IModule(_impl).version();
        LibVersionRegistry.addVersion(version, _impl);
    }

    function versionToImplementationAddress(uint256 _version)
        public
        view
        override
        returns (address)
    {
        LibVersionRegistry.VersionStorage storage s = LibVersionRegistry
        .versionStorage();

        return s.versionToImplementationAddress[_version];
    }

    function implementationAddressToVersion(address _impl)
        public
        view
        override
        returns (uint256)
    {
        LibVersionRegistry.VersionStorage storage s = LibVersionRegistry
        .versionStorage();

        return s.implementationAddressToVersion[_impl];
    }

    function _unpackVersionFromCallData() private pure returns (uint256) {
        return abi.decode(msg.data[4:36], (uint256));
    }

    fallback() external payable {
        LibVersionRegistry.VersionStorage storage s;
        bytes32 position = LibVersionRegistry.VERSION_REGISTRY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
        uint256 version = _unpackVersionFromCallData();
        address implementation = s.versionToImplementationAddress[version];
        require(
            implementation != address(0),
            "provided version does not have implementation"
        );
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )
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

    receive() external payable {}
}
