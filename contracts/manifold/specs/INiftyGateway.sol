// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Nifty builder instance
 */
interface INiftyBuilderInstance {
    function niftyRegistryContract() external view returns (address);
}

/**
 * @dev Nifty registry
 */
interface INiftyRegistry {
    /**
     * @dev function to see if sending key is valid
     */
    function isValidNiftySender(address sending_key) external view returns (bool);
}
