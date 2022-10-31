// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title IVariableSupplyAuction
/// @author neodaoist
/// @notice Interface for Variable Supply Auction
interface IVariableSupplyAuction {
    //

    /// @notice Creates a variable supply auction
    /// @param _tokenContract The address of the ERC-721 drop contract
    /// @param _minimumViableRevenue The minimum revenue the seller aims to generate in this auction --
    /// they can settle the auction below this value, but they cannot _not_ settle if the revenue
    /// generated by any price point + edition size combination would be at least this value
    /// @param _sellerFundsRecipient The address to send funds to once the auction is complete
    /// @param _startTime The Unix time that users can begin placing bids
    /// @param _bidPhaseDuration The length of time of the bid phase in seconds
    /// @param _revealPhaseDuration The length of time of the reveal phase in seconds
    /// @param _settlePhaseDuration The length of time of the settle phase in seconds
    function createAuction(
        address _tokenContract,
        uint256 _minimumViableRevenue,
        address _sellerFundsRecipient,
        uint256 _startTime,
        uint256 _bidPhaseDuration,
        uint256 _revealPhaseDuration,
        uint256 _settlePhaseDuration
    ) external;

    /// @notice Cancels the auction for a given drop
    /// @param _tokenContract The address of the ERC-721 drop contract
    function cancelAuction(address _tokenContract) external;

    /// @notice Places a bid in a variable supply auction
    /// @param _tokenContract The address of the ERC-721 drop contract
    /// @param _commitmentHash The sha256 hash of the sealed bid amount concatenated with
    /// a salt string, both of which need to be included in the subsequent reveal bid tx
    function placeBid(address _tokenContract, bytes32 _commitmentHash) external payable;

    /// @notice Reveals a previously placed bid
    /// @param _tokenContract The address of the ERC-721 drop contract
    /// @param _bidAmount The true bid amount
    /// @param _salt The string which was used, in combination with the true bid amount,
    /// to generate the commitment hash sent with the original placed bid tx
    function revealBid(address _tokenContract, uint256 _bidAmount, string calldata _salt) external;

    /// @notice Calculate edition size and revenue for each possible price point
    /// @param _tokenContract The address of the ERC-721 drop contract
    /// @return A tuple of 3 arrays representing the settle outcomes --
    /// the possible price points at which to settle, along with the 
    /// resulting edition sizes and amounts of revenue generated
    function calculateSettleOutcomes(address _tokenContract) external returns (uint96[] memory, uint16[] memory, uint96[] memory);

    /// @notice Settle an auction at a given price point
    /// @param _tokenContract The address of the ERC-721 drop contract
    /// @param _settlePricePoint The price point at which to settle the auction
    function settleAuction(address _tokenContract, uint96 _settlePricePoint) external;

    /// @notice Check available refund -- if a winning bidder, any additional ether sent above
    /// your bid amount; if not a winning bidder, the full amount of ether sent with your bid
    /// @param _tokenContract The address of the ERC-721 drop contract
    function checkAvailableRefund(address _tokenContract) external view returns (uint96);

    /// @notice Claim refund -- if a winning bidder, any additional ether sent above your
    /// bid amount; if not a winning bidder, the full amount of ether sent with your bid
    /// @param _tokenContract The address of the ERC-721 drop contract
    function claimRefund(address _tokenContract) external;
}
