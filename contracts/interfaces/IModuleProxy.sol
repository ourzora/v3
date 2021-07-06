// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

interface IModuleProxy {
    function registerVersion(address _impl) external;

    function versionToImplementationAddress(uint256 _version)
        external
        view
        returns (address);

    function implementationAddressToVersion(address _impl)
        external
        view
        returns (uint256);
}
