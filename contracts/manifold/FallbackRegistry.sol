// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Recipient} from "./overrides/IRoyaltySplitter.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IFallbackRegistry} from "./overrides/IFallbackRegistry.sol";

contract FallbackRegistry is IFallbackRegistry, Ownable2Step {
    struct TokenFallback {
        address tokenAddress;
        Recipient[] recipients;
    }

    mapping(address => Recipient[]) fallbacks;

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    function setFallback(address tokenAddress, Recipient[] calldata _recipients) public onlyOwner {
        Recipient[] storage recipients = fallbacks[tokenAddress];
        uint256 recipientsLength = _recipients.length;
        ///@solidity memory-safe-assembly
        assembly {
            // overwrite length directly rather than deleting and then updating it each time we push new values
            // this means if the new array is shorter than the old ones, those slots will stay dirty, but they
            // should not be able to be accessed due to the new length
            sstore(recipients.slot, recipientsLength)
        }
        for (uint256 i; i < recipientsLength; ) {
            recipients[i] = _recipients[i];
            unchecked {
                ++i;
            }
        }
    }

    function setFallbacks(TokenFallback[] calldata bundle) external onlyOwner {
        uint256 bundleLength = bundle.length;
        for (uint256 i = 0; i < bundleLength; ) {
            TokenFallback calldata tokenFallback = bundle[i];
            setFallback(tokenFallback.tokenAddress, tokenFallback.recipients);
            unchecked {
                ++i;
            }
        }
    }

    function getRecipients(address tokenAddress) external view returns (Recipient[] memory) {
        return fallbacks[tokenAddress];
    }
}
