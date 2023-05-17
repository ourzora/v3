// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./libraries/SuperRareContracts.sol";

import "./specs/IManifold.sol";
import "./specs/IRarible.sol";
import "./specs/IFoundation.sol";
import "./specs/ISuperRare.sol";
import "./specs/IEIP2981.sol";
import "./specs/IZoraOverride.sol";
import "./specs/IArtBlocksOverride.sol";
import "./IRoyaltyEngineV1.sol";
import "./IRoyaltyRegistry.sol";

/**
 * @dev Engine to lookup royalty configurations
 */
contract RoyaltyEngineV1 is ERC165, OwnableUpgradeable, IRoyaltyEngineV1 {
    using AddressUpgradeable for address;

    // Use int16 for specs to support future spec additions
    // When we add a spec, we also decrement the NONE value
    // Anything > NONE and <= NOT_CONFIGURED is considered not configured
    int16 private constant NONE = -1;
    int16 private constant NOT_CONFIGURED = 0;
    int16 private constant EIP2981 = 1;
    int16 private constant ZORA = 2;

    mapping(address => int16) _specCache;

    address public royaltyRegistry;

    function initialize(address royaltyRegistry_) public initializer {
        __Ownable_init_unchained();
        require(ERC165Checker.supportsInterface(royaltyRegistry_, type(IRoyaltyRegistry).interfaceId));
        royaltyRegistry = royaltyRegistry_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IRoyaltyEngineV1).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Invalidate the cached spec (useful for situations where tooken royalty implementation changes to a different spec)
     */
    function invalidateCachedRoyaltySpec(address tokenAddress) public {
        address royaltyAddress = IRoyaltyRegistry(royaltyRegistry).getRoyaltyLookupAddress(tokenAddress);
        delete _specCache[royaltyAddress];
    }

    /**
     * @dev View function to get the cached spec of a token
     */
    function getCachedRoyaltySpec(address tokenAddress) public view returns (int16) {
        address royaltyAddress = IRoyaltyRegistry(royaltyRegistry).getRoyaltyLookupAddress(tokenAddress);
        return _specCache[royaltyAddress];
    }

    /**
     * @dev See {IRoyaltyEngineV1-getRoyalty}
     */
    function getRoyalty(
        address tokenAddress,
        uint256 tokenId,
        uint256 value
    ) public override returns (address payable[] memory recipients, uint256[] memory amounts) {
        // External call to limit gas
        try this._getRoyaltyAndSpec{gas: 50000}(tokenAddress, tokenId, value) returns (
            address payable[] memory _recipients,
            uint256[] memory _amounts,
            int16 spec,
            address royaltyAddress,
            bool addToCache
        ) {
            if (addToCache) _specCache[royaltyAddress] = spec;
            return (_recipients, _amounts);
        } catch {
            revert("Invalid royalty amount");
        }
    }

    /**
     * @dev See {IRoyaltyEngineV1-getRoyaltyView}.
     */
    function getRoyaltyView(
        address tokenAddress,
        uint256 tokenId,
        uint256 value
    ) public view override returns (address payable[] memory recipients, uint256[] memory amounts) {
        // External call to limit gas
        try this._getRoyaltyAndSpec{gas: 100000}(tokenAddress, tokenId, value) returns (
            address payable[] memory _recipients,
            uint256[] memory _amounts,
            int16,
            address,
            bool
        ) {
            return (_recipients, _amounts);
        } catch {
            revert("Invalid royalty amount");
        }
    }

    /**
     * @dev Get the royalty and royalty spec for a given token
     *
     * returns recipieints array, amounts array, royalty spec, royalty address, whether or not to add to cache
     */
    function _getRoyaltyAndSpec(
        address tokenAddress,
        uint256 tokenId,
        uint256 value
    )
        external
        view
        returns (
            address payable[] memory recipients,
            uint256[] memory amounts,
            int16 spec,
            address royaltyAddress,
            bool addToCache
        )
    {
        require(msg.sender == address(this), "Only Engine");

        royaltyAddress = IRoyaltyRegistry(royaltyRegistry).getRoyaltyLookupAddress(tokenAddress);
        spec = _specCache[royaltyAddress];

        if (spec <= NOT_CONFIGURED && spec > NONE) {
            // No spec configured yet, so we need to detect the spec
            addToCache = true;

            try IEIP2981(royaltyAddress).royaltyInfo(tokenId, value) returns (address recipient, uint256 amount) {
                // Supports EIP2981.  Return amounts
                require(amount < value, "Invalid royalty amount");
                recipients = new address payable[](1);
                amounts = new uint256[](1);
                recipients[0] = payable(recipient);
                amounts[0] = amount;
                return (recipients, amounts, EIP2981, royaltyAddress, addToCache);
            } catch {}
            try IZoraOverride(royaltyAddress).convertBidShares(tokenAddress, tokenId) returns (
                address payable[] memory recipients_,
                uint256[] memory bps
            ) {
                // Support Zora override
                require(recipients_.length == bps.length);
                return (recipients_, _computeAmounts(value, bps), ZORA, royaltyAddress, addToCache);
            } catch {}
            // No supported royalties configured
            return (recipients, amounts, NONE, royaltyAddress, addToCache);
        } else {
            // Spec exists, just execute the appropriate one
            addToCache = false;
            if (spec == NONE) {
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == EIP2981) {
                // EIP2981 spec
                (address recipient, uint256 amount) = IEIP2981(royaltyAddress).royaltyInfo(tokenId, value);
                require(amount < value, "Invalid royalty amount");
                recipients = new address payable[](1);
                amounts = new uint256[](1);
                recipients[0] = payable(recipient);
                amounts[0] = amount;
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == ZORA) {
                // Zora spec
                uint256[] memory bps;
                (recipients, bps) = IZoraOverride(royaltyAddress).convertBidShares(tokenAddress, tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            }
        }
    }

    /**
     * Compute royalty amounts
     */
    function _computeAmounts(uint256 value, uint256[] memory bps) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](bps.length);
        uint256 totalAmount;
        for (uint256 i = 0; i < bps.length; i++) {
            amounts[i] = (value * bps[i]) / 10000;
            totalAmount += amounts[i];
        }
        require(totalAmount < value, "Invalid royalty amount");
        return amounts;
    }
}
