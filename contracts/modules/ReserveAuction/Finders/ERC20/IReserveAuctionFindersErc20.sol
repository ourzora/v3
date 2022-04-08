// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IReserveAuctionFindersErc20
/// @author kulkarohan
/// @notice Interface for Reserve Auction Finders ERC-20
interface IReserveAuctionFindersErc20 {
    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _duration The length of time the auction should run after the first bid
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the auction is complete
    /// @param _startTime The time that users can begin placing bids
    /// @param _bidCurrency The address of the ERC-20 token, or address(0) for ETH, that users must bid with
    /// @param _findersFeeBps The fee to send to the referrer of the winning bid
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint256 _startTime,
        address _bidCurrency,
        uint256 _findersFeeBps
    ) external;

    /// @notice Updates the reserve price for a given auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _reservePrice The new reserve price
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external;

    /// @notice Cancels the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external;

    /// @notice Places a bid on the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _amount The amount to bid
    /// @param _finder The referrer of the bid
    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _finder
    ) external payable;

    /// @notice Ends the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function settleAuction(address _tokenContract, uint256 _tokenId) external;
}
