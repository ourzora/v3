// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ZoraProposalManager} from "./ZoraProposalManager.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";

contract ERC20TransferHelper is BaseTransferHelper {
    using SafeERC20 for IERC20;

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _value
    ) public onlyRegisteredAndApprovedModule(_from) {
        return IERC20(_token).safeTransferFrom(_token, _from, _to, _value);
    }
}
