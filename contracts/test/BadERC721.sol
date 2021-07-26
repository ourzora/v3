// SPDX-License-Identifier: GPL-3.0

// FOR TEST PURPOSES ONLY. NOT PRODUCTION SAFE
pragma solidity 0.8.5;

contract BadERC721 {
    function supportsInterface(bytes4 _interface) public returns (bool) {
        return false;
    }
}
