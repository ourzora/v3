// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

library LibVersionRegistry {
    bytes32 constant VERSION_REGISTRY_STORAGE_POSITION =
        keccak256("version.registry");

    struct VersionStorage {
        mapping(uint256 => address) versionToImplementationAddress;
        mapping(address => uint256) implementationAddressToVersion;
    }

    function versionStorage()
        internal
        pure
        returns (LibVersionRegistry.VersionStorage storage s)
    {
        bytes32 position = VERSION_REGISTRY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function addVersion(uint256 _version, address _impl) internal {
        VersionStorage storage s = versionStorage();
        require(
            s.implementationAddressToVersion[_impl] == 0,
            "LibVersionRegistry::addVersion implementation address already in use"
        );
        require(
            s.versionToImplementationAddress[_version] == address(0),
            "LibVersionRegistry::addVersion version already in use"
        );
        s.implementationAddressToVersion[_impl] = _version;
        s.versionToImplementationAddress[_version] = _impl;
    }
}
