// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 *  Interface for an Art Blocks override
 */
interface IArtBlocksOverride {
    /**
     * @dev Get royalites of a token at a given tokenAddress.
     *      Returns array of receivers and basisPoints.
     *
     *  bytes4(keccak256('getRoyalties(address,uint256)')) == 0x9ca7dc7a
     *
     *  => 0x9ca7dc7a = 0x9ca7dc7a
     */
    function getRoyalties(address tokenAddress, uint256 tokenId) external view returns (address payable[] memory, uint256[] memory);
}
