// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraModuleManager} from "../../../ZoraModuleManager.sol";

/// @title ZoraRegistrar
/// @notice Mock ZORA V3 Registrar
contract ZoraRegistrar {
    ZoraModuleManager internal ZMM;

    function init(ZoraModuleManager _ZMM) public {
        ZMM = _ZMM;
    }

    function registerModule(address _module) public {
        ZMM.registerModule(_module);
    }

    function setRegistrar(address _registrar) public {
        ZMM.setRegistrar(_registrar);
    }
}
