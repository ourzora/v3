// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISuperRareRegistry {
    /**
     * @dev Get the royalty fee percentage for a specific ERC721 contract.
     * @param _contractAddress address ERC721Contract address.
     * @param _tokenId uint256 token ID.
     * @return uint8 wei royalty fee.
     */
    function getERC721TokenRoyaltyPercentage(address _contractAddress, uint256 _tokenId) external view returns (uint8);

    /**
     * @dev Utililty function to calculate the royalty fee for a token.
     * @param _contractAddress address ERC721Contract address.
     * @param _tokenId uint256 token ID.
     * @param _amount uint256 wei amount.
     * @return uint256 wei fee.
     */
    function calculateRoyaltyFee(
        address _contractAddress,
        uint256 _tokenId,
        uint256 _amount
    ) external view returns (uint256);

    /**
     * @dev Get the token creator which will receive royalties of the given token
     * @param _contractAddress address ERC721Contract address.
     * @param _tokenId uint256 token ID.
     */
    function tokenCreator(address _contractAddress, uint256 _tokenId) external view returns (address payable);
}
