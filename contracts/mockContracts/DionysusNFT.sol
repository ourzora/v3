// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DionysusNFT is ERC721URIStorage, Ownable {
    uint256 private currentTokenId = 0;

    constructor() ERC721("DionysusNFT", "d-666") {}

    function mintNFT(address recipient, string memory tokenURI) public onlyOwner returns (uint256) {
        currentTokenId++;

        _mint(recipient, currentTokenId);
        _setTokenURI(currentTokenId, tokenURI);

        return currentTokenId;
    }
}
