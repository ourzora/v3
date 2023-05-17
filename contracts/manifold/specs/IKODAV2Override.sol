// SPDX-License-Identifier: MIT

/// @author: knownorigin.io

pragma solidity ^0.8.0;

interface IKODAV2 {
    function editionOfTokenId(uint256 _tokenId) external view returns (uint256 _editionNumber);

    function artistCommission(uint256 _editionNumber) external view returns (address _artistAccount, uint256 _artistCommission);

    function editionOptionalCommission(uint256 _editionNumber) external view returns (uint256 _rate, address _recipient);
}

interface IKODAV2Override {
    /// @notice Emitted when the royalties fee changes
    event CreatorRoyaltiesFeeUpdated(uint256 _oldCreatorRoyaltiesFee, uint256 _newCreatorRoyaltiesFee);

    /// @notice For the given KO NFT and token ID, return the addresses and the amounts to pay
    function getKODAV2RoyaltyInfo(
        address _tokenAddress,
        uint256 _id,
        uint256 _amount
    ) external view returns (address payable[] memory, uint256[] memory);

    /// @notice Allows the owner() to update the creator royalties
    function updateCreatorRoyalties(uint256 _creatorRoyaltiesFee) external;
}
