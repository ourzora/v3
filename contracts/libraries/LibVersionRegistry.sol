// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

library LibVersionRegistry {
    // keccak256("core.registry")
    bytes32 constant VERSION_REGISTRY_STORAGE_POSITION =
        0x3f3af226decc9238e7d7bff3a1fe46f3dba86ecfd6aa03cf2d9fb8c9ffddf485;

    struct RegistryStorage {
        mapping(uint256 => address) versionToImplementationAddress;
        mapping(address => uint256) implementationAddressToVersion;
    }

    function registryStorage()
        internal
        pure
        returns (LibVersionRegistry.RegistryStorage storage s)
    {
        bytes32 position = VERSION_REGISTRY_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function addVersion(
        uint256 _version,
        address _impl,
        bytes memory _calldata
    ) internal {
        RegistryStorage storage s = registryStorage();
        require(
            s.implementationAddressToVersion[_impl] == 0,
            "LibVersionRegistry::addVersion implementation address already in use"
        );
        require(
            s.versionToImplementationAddress[_version] == address(0),
            "LibVersionRegistry::addVersion version already in use"
        );

        if (_calldata.length != 0) {
            (bool success, bytes memory returnData) = _impl.delegatecall(
                _calldata
            );
            require(
                success,
                string(
                    abi.encodePacked(
                        "LibVersionRegistry::addVersion _impl call failed"
                    )
                )
            );
        }

        s.implementationAddressToVersion[_impl] = _version;
        s.versionToImplementationAddress[_version] = _impl;
    }
}
