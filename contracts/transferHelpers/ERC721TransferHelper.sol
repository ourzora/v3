// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";

/// @title ERC-721 Transfer Helper
/// @author tbtstl <t@zora.co>
/// @notice This contract provides modules the ability to transfer ZORA user ERC-721s with their permission
contract ERC721TransferHelper is BaseTransferHelper {
    constructor(address _approvalsManager) BaseTransferHelper(_approvalsManager) {}

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _tokenId
    ) public onlyApprovedModule(_from) {
        IERC721(_token).safeTransferFrom(_from, _to, _tokenId);
    }

    function transferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _tokenId
    ) public onlyApprovedModule(_from) {
        IERC721(_token).transferFrom(_from, _to, _tokenId);
    }
}
