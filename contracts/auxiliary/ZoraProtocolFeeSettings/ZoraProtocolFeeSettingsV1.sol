// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title ZoraProtocolFeeSettingsV1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows an optional fee percentage and recipient to be set across the ZORA protocol
contract ZoraProtocolFeeSettingsV1 {
    // The address of the owner capable of setting fee parameters
    address public owner;
    uint8 public feePct;
    address public feeRecipient;

    event OwnerUpdated(address indexed newOwner);
    event ProtocolFeeUpdated(address indexed feeRecipient, uint8 feePct);

    modifier onlyOwner() {
        require(owner == msg.sender, "onlyOwner");

        _;
    }

    /// @param _owner the Owner of the protocol fees, ZORA DAO expected
    constructor(address _owner) {
        _setOwner(_owner);
    }

    /// @notice Computes the fee for a given uint256 amount
    /// @param _amount The amount to compute the fee for
    /// @return amount to be paid out to the fee recipient
    function getFeeAmount(uint256 _amount) external view returns (uint256) {
        return (_amount * feePct) / 100;
    }

    /// @notice Sets the owner of the contract
    /// @param _owner the new owner
    function setOwner(address _owner) external onlyOwner {
        _setOwner(_owner);
    }

    /// @notice Sets fee parameters for ZORA protocol.
    /// @param _feeRecipient The fee recipient address to send fees to
    /// @param _feePct The % of transaction value to send to the fee recipient
    function setFeeParams(address _feeRecipient, uint8 _feePct) external onlyOwner {
        require(_feePct <= 100, "setFeeParams must set fee <= 100%");
        require(_feeRecipient != address(0) || _feePct == 0, "setFeeParams fee recipient cannot be 0 address if fee is greater than 0");

        feePct = _feePct;
        feeRecipient = _feeRecipient;

        emit ProtocolFeeUpdated(feeRecipient, feePct);
    }

    function _setOwner(address _owner) private {
        owner = _owner;

        emit OwnerUpdated(_owner);
    }
}
