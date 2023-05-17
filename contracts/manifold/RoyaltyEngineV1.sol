// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {SuperRareContracts} from "./libraries/SuperRareContracts.sol";

import {IManifold} from "./specs/IManifold.sol";
import {IRaribleV1, IRaribleV2} from "./specs/IRarible.sol";
import {IFoundation} from "./specs/IFoundation.sol";
import {ISuperRareRegistry} from "./specs/ISuperRare.sol";
import {IEIP2981} from "./specs/IEIP2981.sol";
import {IZoraOverride} from "./specs/IZoraOverride.sol";
import {IArtBlocksOverride} from "./specs/IArtBlocksOverride.sol";
import {IKODAV2Override} from "./specs/IKODAV2Override.sol";
import {IRoyaltyEngineV1} from "./IRoyaltyEngineV1.sol";
import {IRoyaltyRegistry} from "./IRoyaltyRegistry.sol";
import {IRoyaltySplitter, Recipient} from "./overrides/IRoyaltySplitter.sol";
import {IFallbackRegistry} from "./overrides/IFallbackRegistry.sol";

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
    int16 private constant MANIFOLD = 1;
    int16 private constant RARIBLEV1 = 2;
    int16 private constant RARIBLEV2 = 3;
    int16 private constant FOUNDATION = 4;
    int16 private constant EIP2981 = 5;
    int16 private constant SUPERRARE = 6;
    int16 private constant ZORA = 7;
    int16 private constant ARTBLOCKS = 8;
    int16 private constant KNOWNORIGINV2 = 9;
    int16 private constant ROYALTY_SPLITTER = 10;
    int16 private constant FALLBACK = type(int16).max;

    mapping(address => int16) _specCache;

    address public royaltyRegistry;
    IFallbackRegistry public immutable FALLBACK_REGISTRY;

    constructor(address fallbackRegistry) {
        FALLBACK_REGISTRY = IFallbackRegistry(fallbackRegistry);
    }

    function initialize(address _initialOwner, address royaltyRegistry_) public initializer {
        _transferOwnership(_initialOwner);
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
        try this._getRoyaltyAndSpec{gas: 100000}(tokenAddress, tokenId, value) returns (
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
     * returns recipients array, amounts array, royalty spec, royalty address, whether or not to add to cache
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

            // SuperRare handling
            if (tokenAddress == SuperRareContracts.SUPERRARE_V1 || tokenAddress == SuperRareContracts.SUPERRARE_V2) {
                try ISuperRareRegistry(SuperRareContracts.SUPERRARE_REGISTRY).tokenCreator(tokenAddress, tokenId) returns (address payable creator) {
                    try ISuperRareRegistry(SuperRareContracts.SUPERRARE_REGISTRY).calculateRoyaltyFee(tokenAddress, tokenId, value) returns (
                        uint256 amount
                    ) {
                        recipients = new address payable[](1);
                        amounts = new uint256[](1);
                        recipients[0] = creator;
                        amounts[0] = amount;
                        return (recipients, amounts, SUPERRARE, royaltyAddress, addToCache);
                    } catch {}
                } catch {}
            }
            try IEIP2981(royaltyAddress).royaltyInfo(tokenId, value) returns (address recipient, uint256 amount) {
                require(amount < value, "Invalid royalty amount");
                uint32 recipientSize;
                assembly {
                    recipientSize := extcodesize(recipient)
                }
                if (recipientSize > 0) {
                    try IRoyaltySplitter(recipient).getRecipients() returns (Recipient[] memory splitRecipients) {
                        recipients = new address payable[](splitRecipients.length);
                        amounts = new uint256[](splitRecipients.length);
                        uint256 sum = 0;
                        uint256 splitRecipientsLength = splitRecipients.length;
                        for (uint256 i = 0; i < splitRecipientsLength; ) {
                            Recipient memory splitRecipient = splitRecipients[i];
                            recipients[i] = payable(splitRecipient.recipient);
                            uint256 splitAmount = (splitRecipient.bps * amount) / 10000;
                            amounts[i] = splitAmount;
                            sum += splitAmount;
                            unchecked {
                                ++i;
                            }
                        }
                        // sum can be less than amount, otherwise small-value listings can break
                        require(sum <= amount, "Invalid split");

                        return (recipients, amounts, ROYALTY_SPLITTER, royaltyAddress, addToCache);
                    } catch {}
                }
                // Supports EIP2981.  Return amounts
                recipients = new address payable[](1);
                amounts = new uint256[](1);
                recipients[0] = payable(recipient);
                amounts[0] = amount;
                return (recipients, amounts, EIP2981, royaltyAddress, addToCache);
            } catch {}
            try IManifold(royaltyAddress).getRoyalties(tokenId) returns (address payable[] memory recipients_, uint256[] memory bps) {
                // Supports manifold interface.  Compute amounts
                require(recipients_.length == bps.length);
                return (recipients_, _computeAmounts(value, bps), MANIFOLD, royaltyAddress, addToCache);
            } catch {}
            try IRaribleV2(royaltyAddress).getRaribleV2Royalties(tokenId) returns (IRaribleV2.Part[] memory royalties) {
                // Supports rarible v2 interface. Compute amounts
                recipients = new address payable[](royalties.length);
                amounts = new uint256[](royalties.length);
                uint256 totalAmount;
                for (uint256 i = 0; i < royalties.length; i++) {
                    recipients[i] = royalties[i].account;
                    amounts[i] = (value * royalties[i].value) / 10000;
                    totalAmount += amounts[i];
                }
                require(totalAmount < value, "Invalid royalty amount");
                return (recipients, amounts, RARIBLEV2, royaltyAddress, addToCache);
            } catch {}
            try IRaribleV1(royaltyAddress).getFeeRecipients(tokenId) returns (address payable[] memory recipients_) {
                // Supports rarible v1 interface. Compute amounts
                recipients_ = IRaribleV1(royaltyAddress).getFeeRecipients(tokenId);
                try IRaribleV1(royaltyAddress).getFeeBps(tokenId) returns (uint256[] memory bps) {
                    require(recipients_.length == bps.length);
                    return (recipients_, _computeAmounts(value, bps), RARIBLEV1, royaltyAddress, addToCache);
                } catch {}
            } catch {}
            try IFoundation(royaltyAddress).getFees(tokenId) returns (address payable[] memory recipients_, uint256[] memory bps) {
                // Supports foundation interface.  Compute amounts
                require(recipients_.length == bps.length);
                return (recipients_, _computeAmounts(value, bps), FOUNDATION, royaltyAddress, addToCache);
            } catch {}
            try IZoraOverride(royaltyAddress).convertBidShares(tokenAddress, tokenId) returns (
                address payable[] memory recipients_,
                uint256[] memory bps
            ) {
                // Support Zora override
                require(recipients_.length == bps.length);
                return (recipients_, _computeAmounts(value, bps), ZORA, royaltyAddress, addToCache);
            } catch {}
            try IArtBlocksOverride(royaltyAddress).getRoyalties(tokenAddress, tokenId) returns (
                address payable[] memory recipients_,
                uint256[] memory bps
            ) {
                // Support Art Blocks override
                require(recipients_.length == bps.length);
                return (recipients_, _computeAmounts(value, bps), ARTBLOCKS, royaltyAddress, addToCache);
            } catch {}
            try IKODAV2Override(royaltyAddress).getKODAV2RoyaltyInfo(tokenAddress, tokenId, value) returns (
                address payable[] memory _recipients,
                uint256[] memory _amounts
            ) {
                // Support KODA V2 override
                require(_recipients.length == _amounts.length);
                return (_recipients, _amounts, KNOWNORIGINV2, royaltyAddress, addToCache);
            } catch {}

            try FALLBACK_REGISTRY.getRecipients(tokenAddress) returns (Recipient[] memory _recipients) {
                uint256 recipientsLength = _recipients.length;
                if (recipientsLength > 0) {
                    return _calculateFallback(_recipients, recipientsLength, value, royaltyAddress, addToCache);
                }
            } catch {}

            // No supported royalties configured
            return (recipients, amounts, NONE, royaltyAddress, addToCache);
        } else {
            // Spec exists, just execute the appropriate one
            addToCache = false;
            if (spec == NONE) {
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == FALLBACK) {
                Recipient[] memory _recipients = FALLBACK_REGISTRY.getRecipients(tokenAddress);
                return _calculateFallback(_recipients, _recipients.length, value, royaltyAddress, addToCache);
            } else if (spec == MANIFOLD) {
                // Manifold spec
                uint256[] memory bps;
                (recipients, bps) = IManifold(royaltyAddress).getRoyalties(tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            } else if (spec == RARIBLEV2) {
                // Rarible v2 spec
                IRaribleV2.Part[] memory royalties;
                royalties = IRaribleV2(royaltyAddress).getRaribleV2Royalties(tokenId);
                recipients = new address payable[](royalties.length);
                amounts = new uint256[](royalties.length);
                uint256 totalAmount;
                for (uint256 i = 0; i < royalties.length; i++) {
                    recipients[i] = royalties[i].account;
                    amounts[i] = (value * royalties[i].value) / 10000;
                    totalAmount += amounts[i];
                }
                require(totalAmount < value, "Invalid royalty amount");
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == RARIBLEV1) {
                // Rarible v1 spec
                uint256[] memory bps;
                recipients = IRaribleV1(royaltyAddress).getFeeRecipients(tokenId);
                bps = IRaribleV1(royaltyAddress).getFeeBps(tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            } else if (spec == FOUNDATION) {
                // Foundation spec
                uint256[] memory bps;
                (recipients, bps) = IFoundation(royaltyAddress).getFees(tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            } else if (spec == EIP2981 || spec == ROYALTY_SPLITTER) {
                // EIP2981 spec
                (address recipient, uint256 amount) = IEIP2981(royaltyAddress).royaltyInfo(tokenId, value);
                require(amount < value, "Invalid royalty amount");
                if (spec == ROYALTY_SPLITTER) {
                    Recipient[] memory splitRecipients = IRoyaltySplitter(recipient).getRecipients();
                    recipients = new address payable[](splitRecipients.length);
                    amounts = new uint256[](splitRecipients.length);
                    uint256 sum = 0;
                    uint256 splitRecipientsLength = splitRecipients.length;
                    for (uint256 i = 0; i < splitRecipientsLength; ) {
                        Recipient memory splitRecipient = splitRecipients[i];
                        recipients[i] = payable(splitRecipient.recipient);
                        uint256 splitAmount = (splitRecipient.bps * amount) / 10000;
                        amounts[i] = splitAmount;
                        sum += splitAmount;
                        unchecked {
                            ++i;
                        }
                    }
                    // sum can be less than amount, otherwise small-value listings can break
                    require(sum <= value, "Invalid split");

                    return (recipients, amounts, spec, royaltyAddress, addToCache);
                }
                recipients = new address payable[](1);
                amounts = new uint256[](1);
                recipients[0] = payable(recipient);
                amounts[0] = amount;
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == SUPERRARE) {
                // SUPERRARE spec
                address payable creator = ISuperRareRegistry(SuperRareContracts.SUPERRARE_REGISTRY).tokenCreator(tokenAddress, tokenId);
                uint256 amount = ISuperRareRegistry(SuperRareContracts.SUPERRARE_REGISTRY).calculateRoyaltyFee(tokenAddress, tokenId, value);
                recipients = new address payable[](1);
                amounts = new uint256[](1);
                recipients[0] = creator;
                amounts[0] = amount;
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            } else if (spec == ZORA) {
                // Zora spec
                uint256[] memory bps;
                (recipients, bps) = IZoraOverride(royaltyAddress).convertBidShares(tokenAddress, tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            } else if (spec == ARTBLOCKS) {
                // Art Blocks spec
                uint256[] memory bps;
                (recipients, bps) = IArtBlocksOverride(royaltyAddress).getRoyalties(tokenAddress, tokenId);
                require(recipients.length == bps.length);
                return (recipients, _computeAmounts(value, bps), spec, royaltyAddress, addToCache);
            } else if (spec == KNOWNORIGINV2) {
                // KnownOrigin.io V2 spec (V3 falls under EIP2981)
                (recipients, amounts) = IKODAV2Override(royaltyAddress).getKODAV2RoyaltyInfo(tokenAddress, tokenId, value);
                require(recipients.length == amounts.length);
                return (recipients, amounts, spec, royaltyAddress, addToCache);
            }
        }
    }

    function _calculateFallback(
        Recipient[] memory _recipients,
        uint256 recipientsLength,
        uint256 value,
        address royaltyAddress,
        bool addToCache
    )
        internal
        pure
        returns (
            address payable[] memory recipients,
            uint256[] memory amounts,
            int16 spec,
            address _royaltyAddress,
            bool _addToCache
        )
    {
        recipients = new address payable[](recipientsLength);
        amounts = new uint256[](recipientsLength);
        uint256 totalAmount;
        for (uint256 i = 0; i < recipientsLength; ) {
            Recipient memory recipient = _recipients[i];
            recipients[i] = payable(recipient.recipient);
            uint256 amount = (value * recipient.bps) / 10_000;
            amounts[i] = amount;
            totalAmount += amount;
            unchecked {
                ++i;
            }
        }
        require(totalAmount < value, "Invalid royalty amount");
        return (recipients, amounts, FALLBACK, royaltyAddress, addToCache);
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
