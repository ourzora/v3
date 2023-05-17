// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./IRoyaltySplitter.sol";

/**
 * Multi-receiver EIP2981 reference override implementation
 */
interface IEIP2981MultiReceiverRoyaltyOverride is IERC165 {
    event TokenRoyaltyRemoved(uint256 tokenId);
    event TokenRoyaltySet(uint256 tokenId, uint16 royaltyBPS, Recipient[] recipients);
    event DefaultRoyaltySet(uint16 royaltyBPS, Recipient[] recipients);

    struct TokenRoyaltyConfig {
        uint256 tokenId;
        uint16 royaltyBPS;
        Recipient[] recipients;
    }

    /**
     * @dev Set per token royalties.  Passing a recipient of address(0) will delete any existing configuration
     */
    function setTokenRoyalties(TokenRoyaltyConfig[] calldata royalties) external;

    /**
     * @dev Get all token royalty configurations
     */
    function getTokenRoyalties() external view returns (TokenRoyaltyConfig[] memory);

    /**
     * @dev Get the default royalty
     */
    function getDefaultRoyalty() external view returns (uint16 bps, Recipient[] memory);

    /**
     * @dev Set a default royalty configuration.  Will be used if no token specific configuration is set
     */
    function setDefaultRoyalty(uint16 bps, Recipient[] calldata recipients) external;

    /**
     * @dev Helper function to get all splits contracts
     */
    function getAllSplits() external view returns (address payable[] memory);
}
