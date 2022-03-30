// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IAsksCoreErc20
/// @author kulkarohan
/// @notice Interface for Asks Core ERC-20
interface IAsksCoreErc20 {
    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency of the ask price
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external;

    /// @notice Updates the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency of the ask price
    function setAskPrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external;

    /// @notice Cancels the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAsk(address _tokenContract, uint256 _tokenId) external;

    /// @notice Fills the ask for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _price The price to fill the ask
    /// @param _currency The currency to fill the ask
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _currency
    ) external payable;
}
