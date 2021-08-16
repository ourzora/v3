// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

library LibVersionRegistry {
    bytes32 constant VERSION_REGISTRY_STORAGE_POSITION =
        keccak256("version.registry"); // NIT(@izqui): I would change to 'core.' or 'proxy.', would also pre-compute to avoid calculating the hash on every access

    struct VersionStorage {
        mapping(uint256 => address) versionToImplementationAddress;
        mapping(address => uint256) implementationAddressToVersion;
    }

    // NIT(@izqui): I think registryStorage or versionRegistryStorage would be more clear as to what this is
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

    function addVersion(
        uint256 _version,
        address _impl,
        bytes memory _calldata
    ) internal {
        VersionStorage storage s = versionStorage();
        require(
            s.implementationAddressToVersion[_impl] == 0,
            "LibVersionRegistry::addVersion implementation address already in use"
        );
        require(
            s.versionToImplementationAddress[_version] == address(0),
            "LibVersionRegistry::addVersion version already in use"
        );

        // Q(@izqui): thoughts about enforcing version continuity? Right now it allows registering unordered version numbers in random order
        // E.g. It could feel weird that v4 could be the next version to either v1 or v6 (if v4 was left as a gap)
        // I don't have a very strong opinion on this and enforcing this could cause problems at some point, but I think that
        // requiring the new version to be greater than the previously added version could help maintain sanity without getting too much in the way

        if (_calldata.length != 0) {
            (bool success, bytes memory returnData) = _impl.delegatecall(
                _calldata
            );
            require(
                success,
                string(
                    abi.encodePacked(
                        "LibVersionRegistry::addVersion _impl call failed: ",
                        returnData // ISSUE(@izqui): Return data is an abi-encoded error (`Error(string)`), would need to decode to have the expected result
                    )
                )
            );
        }

        s.implementationAddressToVersion[_impl] = _version;
        s.versionToImplementationAddress[_version] = _impl;
    }
}
