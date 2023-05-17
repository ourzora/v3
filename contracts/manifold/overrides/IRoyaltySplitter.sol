// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

struct Recipient {
    address payable recipient;
    uint16 bps;
}

interface IRoyaltySplitter is IERC165 {
    /**
     * @dev Set the splitter recipients. Total bps must total 10000.
     */
    function setRecipients(Recipient[] calldata recipients) external;

    /**
     * @dev Get the splitter recipients;
     */
    function getRecipients() external view returns (Recipient[] memory);
}
