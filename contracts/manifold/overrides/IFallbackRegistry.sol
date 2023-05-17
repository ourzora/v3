// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Recipient} from "./IRoyaltySplitter.sol";

interface IFallbackRegistry {
    /**
     * @dev Get total recipients for token fees. Note that recipient bps is of gross amount, not share of fee amount,
     *      ie, recipients' BPS will not sum to 10_000, but to the total fee BPS for an order.
     */
    function getRecipients(address tokenAddress) external view returns (Recipient[] memory);
}
