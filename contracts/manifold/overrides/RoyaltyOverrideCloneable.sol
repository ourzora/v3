// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./RoyaltyOverrideCore.sol";

/**
 * Simple EIP2981 reference override implementation
 */
contract EIP2981RoyaltyOverrideCloneable is EIP2981RoyaltyOverrideCore, OwnableUpgradeable {
    function initialize(TokenRoyalty calldata _defaultRoyalty, address initialOwner) public initializer {
        _transferOwnership(initialOwner);
        _setDefaultRoyalty(_defaultRoyalty);
    }

    /**
     * @dev See {IEIP2981RoyaltyOverride-setTokenRoyalties}.
     */
    function setTokenRoyalties(TokenRoyaltyConfig[] calldata royaltyConfigs) external override onlyOwner {
        _setTokenRoyalties(royaltyConfigs);
    }

    /**
     * @dev See {IEIP2981RoyaltyOverride-setDefaultRoyalty}.
     */
    function setDefaultRoyalty(TokenRoyalty calldata royalty) external override onlyOwner {
        _setDefaultRoyalty(royalty);
    }
}
