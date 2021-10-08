// SPDX-License-Identifier: GPL-3.0

// FOR TEST PURPOSES ONLY. NOT PRODUCTION SAFE
pragma solidity 0.8.5;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract TestERC721 is ERC721Enumerable {
    constructor() ERC721("TestERC721", "TEST") {}

    function mint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }
}
