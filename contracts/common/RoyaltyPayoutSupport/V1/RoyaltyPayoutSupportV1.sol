// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IRoyaltyEngineV1} from "../../../external/royalty-registry/contracts/IRoyaltyEngineV1.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OutgoingTransferSupportV1} from "../../OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";

/// @title RoyaltySupportV1
/// @author tbtstl <t@zora.co>
/// @notice This contract extension supports paying out royalties using the Manifold Royalty Registry
contract RoyaltyPayoutSupportV1 is OutgoingTransferSupportV1 {
    IRoyaltyEngineV1 immutable royaltyEngine;

    event RoyaltyPayout(address indexed tokenContract, uint256 indexed tokenId);

    error OnlySelfCallable();

    /// @param _royaltyEngine The Manifold Royalty Engine V1 address
    /// @param _wethAddress WETH token address
    constructor(address _royaltyEngine, address _wethAddress) OutgoingTransferSupportV1(_wethAddress) {
        royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
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
        if (msg.sender != address(this)) {
            revert OnlySelfCallable();
        }
        uint256 remainingAmount = _amount;

        (address payable[] memory recipients, uint256[] memory amounts) = royaltyEngine.getRoyalty(_tokenContract, _tokenId, _amount);

        for (uint256 i = 0; i < recipients.length; i++) {
            // Ensure that we aren't somehow paying out more than we have
            if (remainingAmount < amounts[i]) {
                revert Insolvent();
            }
            _handleOutgoingTransfer(recipients[i], amounts[i], _payoutCurrency, 0);

            remainingAmount -= amounts[i];
        }

        return remainingAmount;
    }
}
