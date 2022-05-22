// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IAsksPrivateEth
/// @author kulkarohan
/// @notice Interface for Asks Private ETH
interface IAsksPrivateEth {
    /// @notice Creates an ask for a given NFT
    /// @param _tokenContract The ERC-721 token address
    /// @param _tokenId The ERC-721 token id
    /// @param _price The price to fill the ask
    /// @param _buyer The address to fill the ask
    function createAsk(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _price,
        address _buyer
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
