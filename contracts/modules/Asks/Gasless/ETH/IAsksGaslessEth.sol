// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface IAsksGaslessEth {
    struct ModuleApprovalSig {
        uint8 v; // The 129th byte and chain ID of the signature
        bytes32 r; // The first 64 bytes of the signature
        bytes32 s; // Bytes 64-128 of the signature
        uint256 deadline; // The deadline at which point the approval expires
    }

    struct GaslessAsk {
        address seller; // The address of the seller
        address tokenContract; // The address of the NFT being sold
        uint256 tokenId; // The ID of the NFT being sold
        uint256 expiry; // The Unix timestamp that this order expires at
        uint256 nonce; // The ID to represent this order (for cancellations)
        uint256 price; // The amount of ETH to sell the NFT for
        ModuleApprovalSig approvalSig; // The user's approval to use this module (optional, empty if already set)
    }

    /// @notice Fills the given signed ask for an NFT
    /// @param _ask The signed ask to fill
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function fillAsk(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable;

    /// @notice Invalidates an off-chain order
    /// @param _ask The signed ask parameters to invalidate
    function cancelAsk(IAsksGaslessEth.GaslessAsk calldata _ask) external;

    /// @notice Broadcasts an order on-chain to indexers
    /// @dev Intentionally a no-op, this can be picked up via EVM traces :)
    /// @param _ask The signed ask parameters to broadcast
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function broadcastAsk(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    /// @notice Checks if a given signature matches the signer of given ask
    /// @param _ask The signed ask parameters to validate
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    /// @return If the given signature matches the ask signature
    function validateAskSig(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external view returns (bool);
}
