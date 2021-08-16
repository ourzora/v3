// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../interfaces/IModule.sol";
import {LibVersionRegistry} from "../libraries/LibVersionRegistry.sol";
import {IModuleProxy} from "../interfaces/IModuleProxy.sol";

// NOTE(@izqui): Since this contract won't be able to conform to EIP-897 (since `implementation()` depends on the version specified in the calldata),
// it won't be compatible with Etherscan's read/write from proxy
contract BaseModuleProxy is IModuleProxy {
    function registerVersion(address _impl, bytes memory _calldata)
        public
        override
    {
        uint256 version = IModule(_impl).version();
        LibVersionRegistry.addVersion(version, _impl, _calldata);
    }

    function versionToImplementationAddress(uint256 _version)
        public
        view
        override
        returns (address)
    {
        LibVersionRegistry.VersionStorage storage s = LibVersionRegistry
        .versionStorage(); // NIT(@izqui): thoughts about increasing the allowed line width in the linter? this line break reads weird

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
        require(
            msg.data.length >= 36,
            "BaseModuleProxy::_unpackVersionFromCallData msg data too short to have a version"
        );
        return abi.decode(msg.data[4:36], (uint256));
    }

    fallback() external payable {
        LibVersionRegistry.VersionStorage storage s; // Q(@izqui): Any reason for not using `LibVersionRegistry.versionStorage()` as in the functions above?
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

    receive() external payable {} // Q(@izqui): When would this contract just receive ETH without calling a function? WETH unwrapping?
}
