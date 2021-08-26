// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

interface IModuleProxy {
    function proposeVersion(address _impl, bytes memory _calldata) external returns (uint256);

    function registerVersion(uint256 _proposalId) external returns (uint256);

    function cancelProposal(uint256 _proposalId) external;

    function setRegistrar(address _registrarAddress) external;

    function versionToImplementationAddress(uint256 _version) external view returns (address);

    function implementationAddressToVersion(address _impl) external view returns (uint256);
}
