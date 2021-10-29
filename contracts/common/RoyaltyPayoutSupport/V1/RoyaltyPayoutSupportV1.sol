// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IRoyaltyEngineV1} from "../../../external/royalty-registry/contracts/IRoyaltyEngineV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";

/// @title RoyaltySupportV1
/// @author tbtstl <t@zora.co>
/// @notice This contract extension supports paying out royalties using the Manifold Royalty Registry and Zora V1 protocol
contract RoyaltyPayoutSupportV1 {
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IRoyaltyEngineV1 royaltyEngine;
    IWETH weth;

    /// @param _zoraV1ProtocolMedia The ZORA NFT Protocol Media Contract address
    /// @param _royaltyEngine The Manifold Royalty Engine V1 address
    /// @param _wethAddress WETH token address
    constructor(
        address _zoraV1ProtocolMedia,
        address _royaltyEngine,
        address _wethAddress
    ) {
        zoraV1Media = IZoraV1Media(_zoraV1ProtocolMedia);
        zoraV1Market = IZoraV1Market(zoraV1Media.marketContract());
        royaltyEngine = IRoyaltyEngineV1(_royaltyEngine);
        weth = IWETH(_wethAddress);
    }

    /// @notice Pays out royalties for given NFTs
    /// @param _tokenContract The NFT Contract to get royalty information from
    /// @param _tokenId, The Token ID to get royalty information from
    /// @param _amount The total sale amount
    /// @param _payoutCurrency The ERC-20 token address to payout royalties in, or address(0) for ETH
    /// @param _gasLimit The gas limit to use when attempting to payout royalties. Uses gasleft() if not provided.
    function _handleRoyaltyPayout(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _payoutCurrency,
        uint256 _gasLimit
    ) internal returns (uint256) {
        if (_tokenContract == address(zoraV1Media)) {
            return _handleZoraPayout(_tokenId, _amount, _payoutCurrency);
        } else {
            // If no gas limit was provided or provided gas limit greater than gas left, just pass the remaining gas.
            uint256 gas = (_gasLimit == 0 || _gasLimit > gasleft()) ? gasleft() : _gasLimit;

            try this._handleRoyaltyEnginePayout{gas: gas, value: msg.value}(_tokenContract, _tokenId, _amount, _payoutCurrency) returns (
                uint256 _remainingFunds
            ) {
                return _remainingFunds;
            } catch {
                return _amount;
            }
        }

        return 1;
    }

    /// @notice Pays out royalties for ZORA V1 NFTs by executing a sale on the underlying market
    /// @param _tokenId, The Token ID to get royalty information from
    /// @param _amount The total sale amount
    /// @param _payoutCurrency The ERC-20 token address to payout royalties in, or address(0) for ETH
    function _handleZoraPayout(
        uint256 _tokenId,
        uint256 _amount,
        address _payoutCurrency
    ) private returns (uint256) {
        return 1;
    }

    /// @notice Pays out royalties for NFTs based on the information returned by the royalty engine
    /// @dev This method is public to enable setting a gas limit when called - see `_handleRoyaltyPayout`.
    /// @param _tokenContract The NFT Contract to get royalty information from
    /// @param _tokenId, The Token ID to get royalty information from
    /// @param _amount The total sale amount
    /// @param _payoutCurrency The ERC-20 token address to payout royalties in, or address(0) for ETH
    function _handleRoyaltyEnginePayout(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _payoutCurrency
    ) public payable returns (uint256) {
        require(msg.sender == address(this), "_handleRoyaltyEnginePayout only self callable");

        return 1;
    }
}
