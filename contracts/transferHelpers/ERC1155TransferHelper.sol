// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";

/// @title ERC-1155 Transfer Helper
/// @author kulkarohan <rohan@zora.co>
/// @notice This contract provides modules the ability to transfer ZORA user ERC-1155s with their permission
contract ERC1155TransferHelper is BaseTransferHelper {
    constructor(address _approvalsManager) BaseTransferHelper(_approvalsManager) {}

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        bytes memory _data
    ) public onlyApprovedModule(_from) {
        IERC1155(_token).safeTransferFrom(_from, _to, _tokenId, _amount, _data);
    }

    function safeBatchTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        bytes memory _data
    ) public onlyApprovedModule(_from) {
        IERC1155(_token).safeBatchTransferFrom(_from, _to, _tokenIds, _amounts, _data);
    }
}
