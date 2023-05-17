// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./IMultiReceiverRoyaltyOverride.sol";
import "./RoyaltySplitter.sol";
import "./IRoyaltySplitter.sol";
import "../specs/IEIP2981.sol";

/**
 * Multi-receiver EIP2981 reference override implementation
 */
abstract contract EIP2981MultiReceiverRoyaltyMultiReceiverOverrideCore is IEIP2981, IEIP2981MultiReceiverRoyaltyOverride, ERC165 {
    uint16 private _defaultRoyaltyBPS;
    address payable private _defaultRoyaltySplitter;

    mapping(uint256 => address payable) private _tokenRoyaltiesSplitter;
    mapping(uint256 => uint16) private _tokenRoyaltiesBPS;
    uint256[] private _tokensWithRoyalties;

    // Address of cloneable splitter contract
    address internal _royaltySplitterCloneable;

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IEIP2981).interfaceId ||
            interfaceId == type(IEIP2981MultiReceiverRoyaltyOverride).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Sets token royalties. When you override this in the implementation contract
     * ensure that you access restrict it to the contract owner or admin
     */
    function _setTokenRoyalties(TokenRoyaltyConfig[] memory royaltyConfigs) internal {
        for (uint256 i; i < royaltyConfigs.length; i++) {
            TokenRoyaltyConfig memory royaltyConfig = royaltyConfigs[i];
            require(royaltyConfig.royaltyBPS < 10000, "Invalid bps");
            Recipient[] memory recipients = royaltyConfig.recipients;
            address payable splitterAddress = _tokenRoyaltiesSplitter[royaltyConfig.tokenId];
            if (recipients.length == 0) {
                if (splitterAddress != address(0)) {
                    IRoyaltySplitter(splitterAddress).setRecipients(recipients);
                }
                delete _tokenRoyaltiesBPS[royaltyConfig.tokenId];
                emit TokenRoyaltyRemoved(royaltyConfig.tokenId);
            } else {
                if (splitterAddress == address(0)) {
                    splitterAddress = payable(Clones.clone(_royaltySplitterCloneable));
                    RoyaltySplitter(splitterAddress).initialize(recipients);
                    _tokenRoyaltiesSplitter[royaltyConfig.tokenId] = splitterAddress;
                    _tokensWithRoyalties.push(royaltyConfig.tokenId);
                } else {
                    IRoyaltySplitter(splitterAddress).setRecipients(recipients);
                }
                _tokenRoyaltiesBPS[royaltyConfig.tokenId] = royaltyConfig.royaltyBPS;
                emit TokenRoyaltySet(royaltyConfig.tokenId, royaltyConfig.royaltyBPS, recipients);
            }
        }
    }

    /**
     * @dev Sets default royalty. When you override this in the implementation contract
     * ensure that you access restrict it to the contract owner or admin
     */
    function _setDefaultRoyalty(uint16 bps, Recipient[] memory recipients) internal {
        require(bps < 10000, "Invalid bps");
        if (_defaultRoyaltySplitter == address(0)) {
            _defaultRoyaltySplitter = payable(Clones.clone(_royaltySplitterCloneable));
            RoyaltySplitter(_defaultRoyaltySplitter).initialize(recipients);
        } else {
            IRoyaltySplitter(_defaultRoyaltySplitter).setRecipients(recipients);
        }
        _defaultRoyaltyBPS = bps;
        emit DefaultRoyaltySet(bps, recipients);
    }

    /**
     * @dev See {IEIP2981MultiReceiverRoyaltyOverride-getTokenRoyalties}.
     */
    function getTokenRoyalties() external view override returns (TokenRoyaltyConfig[] memory royaltyConfigs) {
        royaltyConfigs = new TokenRoyaltyConfig[](_tokensWithRoyalties.length);
        for (uint256 i; i < _tokensWithRoyalties.length; ++i) {
            TokenRoyaltyConfig memory royaltyConfig;
            uint256 tokenId = _tokensWithRoyalties[i];
            address splitterAddress = _tokenRoyaltiesSplitter[tokenId];
            if (splitterAddress != address(0)) {
                royaltyConfig.recipients = IRoyaltySplitter(splitterAddress).getRecipients();
            }
            royaltyConfig.tokenId = tokenId;
            royaltyConfig.royaltyBPS = _tokenRoyaltiesBPS[tokenId];
            royaltyConfigs[i] = royaltyConfig;
        }
    }

    /**
     * @dev See {IEIP2981MultiReceiverRoyaltyOverride-getDefaultRoyalty}.
     */
    function getDefaultRoyalty() external view override returns (uint16 bps, Recipient[] memory recipients) {
        if (_defaultRoyaltySplitter != address(0)) {
            recipients = IRoyaltySplitter(_defaultRoyaltySplitter).getRecipients();
        }
        return (_defaultRoyaltyBPS, recipients);
    }

    /**
     * @dev See {IEIP2981MultiReceiverRoyaltyOverride-royaltyInfo}.
     */
    function royaltyInfo(uint256 tokenId, uint256 value) public view override returns (address, uint256) {
        if (_tokenRoyaltiesSplitter[tokenId] != address(0)) {
            return (_tokenRoyaltiesSplitter[tokenId], (value * _tokenRoyaltiesBPS[tokenId]) / 10000);
        }
        if (_defaultRoyaltySplitter != address(0) && _defaultRoyaltyBPS != 0) {
            return (_defaultRoyaltySplitter, (value * _defaultRoyaltyBPS) / 10000);
        }
        return (address(0), 0);
    }

    /**
     * @dev See {IEIP2981MultiReceiverRoyaltyOverride-getAllSplits}.
     */
    function getAllSplits() external view override returns (address payable[] memory splits) {
        uint256 startingIndex;
        uint256 endingIndex = _tokensWithRoyalties.length;
        if (_defaultRoyaltySplitter != address(0)) {
            splits = new address payable[](1 + _tokensWithRoyalties.length);
            splits[0] = _defaultRoyaltySplitter;
            startingIndex = 1;
            ++endingIndex;
        } else {
            // unreachable in practice
            splits = new address payable[](_tokensWithRoyalties.length);
        }
        for (uint256 i = startingIndex; i < endingIndex; ++i) {
            splits[i] = _tokenRoyaltiesSplitter[_tokensWithRoyalties[i - startingIndex]];
        }
    }

    function getRecipients() public view returns (Recipient[] memory) {
        return RoyaltySplitter(_defaultRoyaltySplitter).getRecipients();
    }
}
