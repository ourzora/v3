// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraModuleFeeToken} from "./ZoraModuleFeeToken.sol";

/// @title ZoraProtocolFeeSettingsV1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows an optional fee percentage and recipient to be set for individual ZORA modules
/// TODO: There are some gas savings to be had by unifying this contract with ZoraModuleFeeToken
contract ZoraProtocolFeeSettingsV1 {
    // The address of the owner capable of setting fee parameters
    ZoraModuleFeeToken moduleFeeToken;

    struct FeeSetting {
        // TODO: maybe we should make this uint16 to allow up increments of 0.1% or 0.01%
        uint8 feePct;
        address feeRecipient;
    }
    mapping(address => FeeSetting) public moduleFeeSetting;

    event OwnerUpdated(address indexed newOwner);
    event ProtocolFeeUpdated(address indexed module, address feeRecipient, uint8 feePct);

    // Only allow the module fee owner to access the function
    modifier onlyOwner(address _module) {
        uint256 tokenId = moduleFeeToken.moduleToTokenId(_module);
        require(moduleFeeToken.ownerOf(tokenId) == msg.sender, "onlyOwner");

        _;
    }

    constructor(address _moduleFeeToken) {
        moduleFeeToken = ZoraModuleFeeToken(_moduleFeeToken);
    }

    /// @notice Computes the fee for a given uint256 amount
    /// @param _module The module to compute the fee for
    /// @param _amount The amount to compute the fee for
    /// @return amount to be paid out to the fee recipient
    function getFeeAmount(address _module, uint256 _amount) external view returns (uint256) {
        return (_amount * moduleFeeSetting[_module].feePct) / 100;
    }

    /// @notice Sets fee parameters for ZORA protocol.
    /// @param _module The module to apply the fee settings to
    /// @param _feeRecipient The fee recipient address to send fees to
    /// @param _feePct The % of transaction value to send to the fee recipient
    function setFeeParams(
        address _module,
        address _feeRecipient,
        uint8 _feePct
    ) external onlyOwner(_module) {
        require(_feePct <= 100, "setFeeParams must set fee <= 100%");
        require(_feeRecipient != address(0) || _feePct == 0, "setFeeParams fee recipient cannot be 0 address if fee is greater than 0");

        moduleFeeSetting[_module] = FeeSetting(_feePct, _feeRecipient);

        emit ProtocolFeeUpdated(_module, _feeRecipient, _feePct);
    }
}
