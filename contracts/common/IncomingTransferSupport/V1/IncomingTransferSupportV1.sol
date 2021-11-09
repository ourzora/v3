// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";

contract IncomingTransferSupportV1 {
    using SafeERC20 for IERC20;

    ERC20TransferHelper immutable erc20TransferHelper;

    error MsgValueLessThanExpectedAmount();
    error TransferCallDidNotTransferExpectedAmount();

    constructor(address _erc20TransferHelper) {
        erc20TransferHelper = ERC20TransferHelper(_erc20TransferHelper);
    }

    /// @notice Handle an incoming funds transfer, ensuring the sent amount is valid and the sender is solvent
    /// @param _amount The amount to be received
    /// @param _currency The currency to receive funds in, or address(0) for ETH
    function _handleIncomingTransfer(uint256 _amount, address _currency) internal {
        if (_currency == address(0)) {
            if (msg.value < _amount) {
                revert MsgValueLessThanExpectedAmount();
            }
        } else {
            // We must check the balance that was actually transferred to this contract,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            erc20TransferHelper.safeTransferFrom(_currency, msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            if ((beforeBalance + _amount) != afterBalance) {
                revert TransferCallDidNotTransferExpectedAmount();
            }
        }
    }
}
