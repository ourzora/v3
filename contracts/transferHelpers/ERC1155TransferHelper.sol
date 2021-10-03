// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ZoraProposalManager} from "../ZoraProposalManager.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";

contract ERC1155TransferHelper is BaseTransferHelper {
    constructor(address _approvalsManager) BaseTransferHelper(_approvalsManager) {}

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _tokenID,
        uint256 _amount,
        bytes memory _data
    ) public onlyApprovedModule(_from) {
        IERC1155(_token).safeTransferFrom(_from, _to, _tokenID, _amount, _data);
    }

    function safeBatchTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256[] memory _tokenIDs,
        uint256[] memory _amounts,
        bytes memory _data
    ) public onlyApprovedModule(_from) {
        IERC1155(_token).safeBatchTransferFrom(_from, _to, _tokenIDs, _amounts, _data);
    }
}
