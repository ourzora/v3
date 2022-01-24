// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC1155TransferHelper} from "../../../transferHelpers/ERC1155TransferHelper.sol";

/// @title TransferModule
/// @notice FOR TEST PURPOSES ONLY.
contract TransferModule is ERC1155Holder {
    address erc20TransferHelper;
    address erc721TransferHelper;
    address erc1155TransferHelper;

    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _erc1155TransferHelper
    ) {
        erc20TransferHelper = _erc20TransferHelper;
        erc721TransferHelper = _erc721TransferHelper;
        erc1155TransferHelper = _erc1155TransferHelper;
    }

    function depositERC20(
        address _tokenContract,
        address _from,
        uint256 _amount
    ) public {
        ERC20TransferHelper(erc20TransferHelper).safeTransferFrom(_tokenContract, _from, address(this), _amount);
    }

    function depositERC721(
        address _tokenContract,
        address _from,
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).transferFrom(_tokenContract, _from, address(this), _tokenId);
    }

    function safeDepositERC721(
        address _tokenContract,
        address _from,
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).safeTransferFrom(_tokenContract, _from, address(this), _tokenId);
    }

    function safeDepositERC1155(
        address _tokenContract,
        address _from,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeTransferFrom(
            _tokenContract,
            _from,
            address(this),
            _tokenId,
            _amount,
            ""
        );
    }

    function safeBatchDepositERC1155(
        address _tokenContract,
        address _from,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeBatchTransferFrom(
            _tokenContract,
            _from,
            address(this),
            _tokenIds,
            _amounts,
            ""
        );
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
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).transferFrom(_tokenContract, address(this), _to, _tokenId);
    }

    function safeWithdrawERC721(
        address _tokenContract,
        address _to,
        uint256 _tokenId
    ) public {
        ERC721TransferHelper(erc721TransferHelper).safeTransferFrom(_tokenContract, address(this), _to, _tokenId);
    }

    function safeWithdrawERC1155(
        address _tokenContract,
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeTransferFrom(
            _tokenContract,
            address(this),
            _to,
            _tokenId,
            _amount,
            ""
        );
    }

    function safeBatchWithdrawERC1155(
        address _tokenContract,
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) public {
        ERC1155TransferHelper(erc1155TransferHelper).safeBatchTransferFrom(
            _tokenContract,
            address(this),
            _to,
            _tokenIds,
            _amounts,
            ""
        );
    }
}
