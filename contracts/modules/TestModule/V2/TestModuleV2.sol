// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC1155TransferHelper} from "../../../transferHelpers/ERC1155TransferHelper.sol";

import "hardhat/console.sol";

contract TestModuleV2 is ERC1155Holder {
    address erc1155TransferHelper;

    constructor(address _erc1155TransferHelper) {
        erc1155TransferHelper = _erc1155TransferHelper;
    }

    function depositERC1155(
        address _tokenContract,
        address _from,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeTransferFrom(_tokenContract, _from, address(this), _tokenId, _amount, "");
    }

    function withdrawERC1155(
        address _tokenContract,
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeTransferFrom(_tokenContract, address(this), _to, _tokenId, _amount, "");
    }

    function batchDepositERC1155(
        address _tokenContract,
        address _from,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeBatchTransferFrom(_tokenContract, _from, address(this), _tokenIds, _amounts, "");
    }

    function batchWithdrawERC1155(
        address _tokenContract,
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeBatchTransferFrom(_tokenContract, address(this), _to, _tokenIds, _amounts, "");
    }
}
