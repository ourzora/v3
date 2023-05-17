// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/proxy/Clones.sol";
import {EIP2981RoyaltyOverrideCloneable} from "./RoyaltyOverrideCloneable.sol";
import {EIP2981MultiReceiverRoyaltyOverrideCloneable} from "./MultiReceiverRoyaltyOverrideCloneable.sol";
import {IRoyaltyRegistry} from "../IRoyaltyRegistry.sol";
import {Recipient} from "./IRoyaltySplitter.sol";

/**
 * Clone Factory for EIP2981 reference override implementation
 */
contract EIP2981RoyaltyOverrideFactory {
    address public immutable SINGLE_RECIPIENT_ORIGIN_ADDRESS;
    address public immutable MULTI_RECIPIENT_ORIGIN_ADDRESS;
    address payable public immutable ROYALTY_SPLITTER_ORIGIN_ADDRESS;

    error InvalidRoyaltyRegistryAddress();

    uint256 constant INVALID_ROYALTY_REGISTRY_ADDRESS_SELECTOR = 0x1c491d3;

    event EIP2981RoyaltyOverrideCreated(address newEIP2981RoyaltyOverride);

    constructor(
        address singleOrigin,
        address multiOrigin,
        address payable royaltySplitterOrigin
    ) {
        SINGLE_RECIPIENT_ORIGIN_ADDRESS = singleOrigin;
        MULTI_RECIPIENT_ORIGIN_ADDRESS = multiOrigin;
        ROYALTY_SPLITTER_ORIGIN_ADDRESS = royaltySplitterOrigin;
    }

    function createOverrideAndRegister(
        address royaltyRegistry,
        address tokenAddress,
        EIP2981RoyaltyOverrideCloneable.TokenRoyalty calldata defaultRoyalty
    ) public returns (address) {
        address clone = Clones.clone(SINGLE_RECIPIENT_ORIGIN_ADDRESS);
        EIP2981RoyaltyOverrideCloneable(clone).initialize(defaultRoyalty, msg.sender);
        emit EIP2981RoyaltyOverrideCreated(clone);
        registerOverride(royaltyRegistry, tokenAddress, clone);
        return clone;
    }

    function createOverrideAndRegister(
        address royaltyRegistry,
        address tokenAddress,
        uint16 defaultBps,
        Recipient[] calldata defaultRecipients
    ) public returns (address) {
        address clone = Clones.clone(MULTI_RECIPIENT_ORIGIN_ADDRESS);
        EIP2981MultiReceiverRoyaltyOverrideCloneable(clone).initialize(ROYALTY_SPLITTER_ORIGIN_ADDRESS, defaultBps, defaultRecipients, msg.sender);
        emit EIP2981RoyaltyOverrideCreated(clone);
        registerOverride(royaltyRegistry, tokenAddress, clone);
        return clone;
    }

    function registerOverride(
        address royaltyRegistry,
        address tokenAddress,
        address lookupAddress
    ) internal {
        // encode setRoyaltyLookupAddress call with tokenAddress and lookupAddress and also append msg.sender to calldata.
        // Including the original msg.sender allows the registry to securely verify the caller is the owner of the token
        bytes memory data = abi.encodeWithSelector(IRoyaltyRegistry.setRoyaltyLookupAddress.selector, tokenAddress, lookupAddress, msg.sender);

        // check success and return data, and bubble up original revert reason if call was unsuccessful
        ///@solidity memory-safe-assembly
        assembly {
            // clear first word of scratch space, where we will store one word of returndata
            // if the call results in no returndata is available, this would not be overwritten otherwise
            mstore(0, 0)
            let success := call(gas(), royaltyRegistry, 0, add(data, 0x20), mload(data), 0, 0x20)

            // check if call succeeded
            if iszero(success) {
                // copy all of returndata to memory starting at 0; we don't have to worry about dirtying memory since
                // we are reverting.
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            // check if returned boolean is true, since a successful call does not guarantee a successful execution
            let returned := mload(0)
            if iszero(eq(returned, 1)) {
                mstore(0, INVALID_ROYALTY_REGISTRY_ADDRESS_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }
}
