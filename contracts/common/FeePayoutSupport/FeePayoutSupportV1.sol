// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IRoyaltyEngineV1} from "@manifoldxyz/royalty-registry-solidity/contracts/IRoyaltyEngineV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ZoraProtocolFeeSettingsV1} from "../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettingsV1.sol";
import {OutgoingTransferSupportV1} from "../OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";

/// @title FeePayoutSupportV1
/// @author tbtstl <t@zora.co>
/// @notice This contract extension supports paying out protocol fees and royalties
contract FeePayoutSupportV1 is OutgoingTransferSupportV1 {
    IRoyaltyEngineV1 immutable royaltyEngine;
    ZoraProtocolFeeSettingsV1 immutable protocolFeeSettings;

    event RoyaltyPayout(address indexed tokenContract, uint256 indexed tokenId);

    /// @param _royaltyEngine The Manifold Royalty Engine V1 address
    /// @param _protocolFeeSettings The ZoraProtocolFeeSettingsV1 address
    /// @param _wethAddress WETH address
    constructor(
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _wethAddress
    ) OutgoingTransferSupportV1(_wethAddress) {
        royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
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

    /// @notice Pays out royalties for given NFTs
    /// @param _tokenContract The NFT contract address to get royalty information from
    /// @param _tokenId, The Token ID to get royalty information from
    /// @param _amount The total sale amount
    /// @param _payoutCurrency The ERC-20 token address to payout royalties in, or address(0) for ETH
    /// @param _gasLimit The gas limit to use when attempting to payout royalties. Uses gasleft() if not provided.
    /// @return remaining funds after paying out royalties
    function _handleRoyaltyPayout(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _payoutCurrency,
        uint256 _gasLimit
    ) internal returns (uint256, bool) {
        // If no gas limit was provided or provided gas limit greater than gas left, just pass the remaining gas.
        uint256 gas = (_gasLimit == 0 || _gasLimit > gasleft()) ? gasleft() : _gasLimit;
        uint256 remainingFunds;
        bool success;

        // External call ensuring contract doesn't run out of gas paying royalties
        try this._handleRoyaltyEnginePayout{gas: gas}(_tokenContract, _tokenId, _amount, _payoutCurrency) returns (uint256 _remainingFunds) {
            remainingFunds = _remainingFunds;
            success = true;

            emit RoyaltyPayout(_tokenContract, _tokenId);
        } catch {
            remainingFunds = _amount;
            success = false;
        }

        return (remainingFunds, success);
    }

    /// @notice Pays out royalties for NFTs based on the information returned by the royalty engine
    /// @dev This method is external to enable setting a gas limit when called - see `_handleRoyaltyPayout`.
    /// @param _tokenContract The NFT Contract to get royalty information from
    /// @param _tokenId, The Token ID to get royalty information from
    /// @param _amount The total sale amount
    /// @param _payoutCurrency The ERC-20 token address to payout royalties in, or address(0) for ETH
    /// @return remaining funds after paying out royalties
    function _handleRoyaltyEnginePayout(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _payoutCurrency
    ) external payable returns (uint256) {
        require(msg.sender == address(this), "_handleRoyaltyEnginePayout only self callable");
        uint256 remainingAmount = _amount;

        (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyalty(_tokenContract, _tokenId, _amount);

        for (uint256 i = 0; i < recipients.length; i++) {
            // Ensure that we aren't somehow paying out more than we have
            require(remainingAmount >= amounts[i], "insolvent");
            _handleOutgoingTransfer(recipients[i], amounts[i], _payoutCurrency, 0);

            remainingAmount -= amounts[i];
        }

        return remainingAmount;
    }
}
