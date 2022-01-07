// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title ZoraModuleFeeToken
/// @author tbtstl <t@zora.co>
/// @notice This NFT contract allows a holder to set a protocol fee for their token's corresponding ZORA module
contract ZoraModuleFeeToken is ERC721 {
    address private owner;
    address public minter;
    uint256 public tokenCount;
    mapping(uint256 => address) public tokenIdToModule;
    mapping(address => uint256) public moduleToTokenId;

    constructor() ERC721("ZoraModuleFeeToken", "ZMFT") {
        owner = msg.sender;
    }

    /// @param _minter The address that can mint new NFTs (expected ZoraProposalManager address)
    function init(address _minter) external {
        require(msg.sender == owner, "init only owner");
        require(minter == address(0), "init already initialized");

        minter = _minter;
    }

    function mint(address _to, address _module) external returns (uint256) {
        require(msg.sender == minter, "mint onlyMinter");

        uint256 tokenId = tokenCount;

        _mint(_to, tokenId);
        tokenCount++;

        tokenIdToModule[tokenId] = _module;
        moduleToTokenId[_module] = tokenId;

        return tokenId;
    }
}
