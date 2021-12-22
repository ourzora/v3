// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {OutgoingTransferSupportV1} from "../OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";
import {ZoraProtocolFeeSettingsV1} from "../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettingsV1.sol";

/// @title ProtocolFeeSupportV1
/// @author tbtstl <t@zora.co>
/// @notice This contract extension supports paying out a protocol fee
contract ProtocolFeePayoutSupportV1 is OutgoingTransferSupportV1 {
    ZoraProtocolFeeSettingsV1 immutable protocolFeeSettings;

    /// @param _protocolFeeSettings The ZoraProtocolFeeSettingsV1 address
    /// @param _wethAddress WETH token address
    constructor(address _protocolFeeSettings, address _wethAddress) OutgoingTransferSupportV1(_wethAddress) {
        protocolFeeSettings = ZoraProtocolFeeSettingsV1(_protocolFeeSettings);
    }

    /// @notice Pays out protocol fee to protocol fee recipient
    /// @param _amount the sale amount
    /// @param _payoutCurrency the currency amount to pay the fee in
    /// @return remaining funds after paying protocol fee
    function _handleProtocolFeePayout(uint256 _amount, address _payoutCurrency) internal returns (uint256) {
        uint256 protocolFee = protocolFeeSettings.getFeeAmount(_amount);
        _handleOutgoingTransfer(protocolFeeSettings.feeRecipient(), protocolFee, _payoutCurrency, 0);

        return _amount - protocolFee;
    }
}
