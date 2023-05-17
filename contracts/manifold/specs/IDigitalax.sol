// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Digitalax nfts
 */
interface IDigitalax {
    function accessControls() external view returns (address);
}

/**
 * @dev Digitalax Access Controls Simple
 */
interface IDigitalaxAccessControls {
    function hasAdminRole(address _account) external view returns (bool);
}
