// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ZoraModuleManager} from "../../../ZoraModuleManager.sol";

/// @title Zorb
/// @notice Mock ZORA V3 User
contract Zorb is ERC721Holder, ERC1155Holder {
    ZoraModuleManager internal ZMM;

    constructor(address _ZMM) {
        ZMM = ZoraModuleManager(_ZMM);
    }

    /// ------------ ZORA Module Approvals ------------

    function setApprovalForModule(address _module, bool _approved) public {
        ZMM.setApprovalForModule(_module, _approved);
    }

    function setBatchApprovalForModules(address[] memory _modules, bool _approved) public {
        ZMM.setBatchApprovalForModules(_modules, _approved);
    }

    function setApprovalForModuleBySig(
        address _module,
        address _user,
        bool _approved,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        ZMM.setApprovalForModuleBySig(_module, _user, _approved, _deadline, v, r, s);
    }

    /// ------------ ETH Receivable ------------

    event Received(address sender, uint256 amount, uint256 balance);

    receive() external payable {
        emit Received(msg.sender, msg.value, address(this).balance);
    }
}
