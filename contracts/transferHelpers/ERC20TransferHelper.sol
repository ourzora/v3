// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";
import {ITurnstile} from "../csr/ITurnstile.sol";

/// @title ERC-20 Transfer Helper
/// @author tbtstl <t@zora.co>
/// @notice This contract provides modules the ability to transfer ZORA user ERC-20s with their permission
contract ERC20TransferHelper is BaseTransferHelper {
    using SafeERC20 for IERC20;

    constructor(address _approvalsManager) BaseTransferHelper(_approvalsManager) {
        ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44).assign(22); //sets Canto CSR parameters
    }

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _value
    ) public onlyApprovedModule(_from) {
        IERC20(_token).safeTransferFrom(_from, _to, _value);
    }
}
