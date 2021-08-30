// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.5;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ZoraProposalManager} from "../ZoraProposalManager.sol";
import {BaseTransferHelper} from "./BaseTransferHelper.sol";

contract ERC20TransferHelper is BaseTransferHelper {
    using SafeERC20 for IERC20;

    constructor(address _proposalManager, address _approvalsManager) {
        require(_proposalManager != address(0), "must set proposal manager to non-zero address");
        require(_approvalsManager != address(0), "must set approvals manager to non-zero address");

        proposalManager = _proposalManager;
        approvalsManager = _approvalsManager;
    }

    function safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _value
    ) public onlyRegisteredAndApprovedModule(_from) {
        return IERC20(_token).safeTransferFrom(_from, _to, _value);
    }
}
