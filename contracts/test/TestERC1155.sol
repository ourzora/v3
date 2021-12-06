// SPDX-License-Identifier: GPL-3.0

// FOR TEST PURPOSES ONLY. NOT PRODUCTION SAFE
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract TestERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(
        address _to,
        uint256 _tokenID,
        uint256 _amount
    ) public {
        _mint(_to, _tokenID, _amount, "");
    }

    function mintBatch(
        address _to,
        uint256[] memory _tokenIDs,
        uint256[] memory _amounts
    ) public {
        _mintBatch(_to, _tokenIDs, _amounts, "");
    }
}
