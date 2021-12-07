// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";

import "hardhat/console.sol";

contract TestModuleV1 {
    address erc20TransferHelper;
    address erc721TransferHelper;

    constructor(address _erc20TransferHelper, address _erc721TransferHelper) {
        erc20TransferHelper = _erc20TransferHelper;
        erc721TransferHelper = _erc721TransferHelper;
    }

    function depositERC20(
        address _tokenContract,
        address _from,
        uint256 _amount
    ) public {
        ERC20TransferHelper(erc20TransferHelper).safeTransferFrom(_tokenContract, _from, address(this), _amount);
    }

    function safeDepositERC721(
        address _tokenContract,
        address _from,
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).safeTransferFrom(_tokenContract, _from, address(this), _tokenId);
    }

    function depositERC721(
        address _tokenContract,
        address _from,
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).transferFrom(_tokenContract, _from, address(this), _tokenId);
    }

    function withdrawERC20(
        address _tokenContract,
        address _to,
        uint256 _amount
    ) public {
        ERC20TransferHelper(erc20TransferHelper).safeTransferFrom(_tokenContract, address(this), _to, _amount);
    }

    function withdrawERC721(
        address _tokenContract,
        address _to,
        uint256 _tokenID
    ) public {
        ERC721TransferHelper(erc721TransferHelper).transferFrom(_tokenContract, address(this), _to, _tokenID);
    }

    function safeWithdrawERC721(
        address _tokenContract,
        address _to,
        uint256 _tokenID
    ) public {
        ERC721TransferHelper(erc721TransferHelper).safeTransferFrom(_tokenContract, address(this), _to, _tokenID);
    }
}
