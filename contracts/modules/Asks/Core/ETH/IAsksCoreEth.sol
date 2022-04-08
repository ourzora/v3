// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IAsksCoreEth
/// @author kulkarohan
/// @notice Interface for Asks Core ETH
interface IAsksCoreEth {
    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price
    ) external;

    /// @notice Updates the ask price for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The ask price to set
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price
    ) external;

    /// @notice Cancels the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external;

    /// @notice Fills the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function fillAsk(address _tokenContract, uint256 _tokenId) external payable;
}
