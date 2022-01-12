// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraProtocolFeeSettings} from "./auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";

/// @title ZoraModuleManager
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to add & access modules on ZORA V3, plus utilize the ZORA transfer helpers
contract ZoraModuleManager {
    /// @notice The registrar address that can register modules
    address public registrar;

    /// @notice The module fee NFT contract to mint from upon module registration
    ZoraProtocolFeeSettings public moduleFeeToken;

    /// @notice Mapping of each user to module approval in the ZORA registry
    /// @dev User address => Module address => Approved
    mapping(address => mapping(address => bool)) public userApprovals;

    /// @notice A mapping of module addresses to module data
    mapping(address => bool) public moduleRegistered;

    modifier onlyRegistrar() {
        require(msg.sender == registrar, "ZMM::onlyRegistrar must be registrar");
        _;
    }

    event ModuleRegistered(address indexed module);

    event ModuleApprovalSet(address indexed user, address indexed module, bool approved);

    event RegistrarChanged(address indexed newRegistrar);

    /// @param _registrar The initial registrar for the manager
    /// @param _feeToken The module fee token contract to mint from upon module registration
    constructor(address _registrar, address _feeToken) {
        require(_registrar != address(0), "ZMM::must set registrar to non-zero address");

        registrar = _registrar;
        moduleFeeToken = ZoraProtocolFeeSettings(_feeToken);
    }

    /**
     ┌─┐                                                         
     ║"│                                                         
     └┬┘                                                         
     ┌┼┐                                                         
      │                                       ┌─────────────────┐
     ┌┴┐                                      │ZoraModuleManager│
    User                                      └────────┬────────┘
     │ isModuleApproved(address _user, address _module)│         
     │ ────────────────────────────────────────────────>         
     │                                                 │         
     │                 return <boolean>                │         
     │ <────────────────────────────────────────────────         
    User                                      ┌────────┴────────┐
     ┌─┐                                      │ZoraModuleManager│
     ║"│                                      └─────────────────┘
     └┬┘                                                         
     ┌┼┐                                                         
      │                                                          
     ┌┴┐                                                         
    */

    /// @notice Returns true if the user has approved a given module, false otherwise
    /// @param _user The user to check approvals for
    /// @param _module The module to check approvals for
    /// @return True if the module has been approved by the user, false otherwise
    function isModuleApproved(address _user, address _module) external view returns (bool) {
        return userApprovals[_user][_module];
    }

    /**
            ┌─┐                                                                                                              
            ║"│                                                                                                              
            └┬┘                                                                                                              
            ┌┼┐                                                                                                              
             │                                            ┌─────────────────┐                                                
            ┌┴┐                                           │ZoraModuleManager│                                                
            User                                          └────────┬────────┘                                                
            │ setApprovalForModule(address _module, bool _approved)│                                                         
            │ ─────────────────────────────────────────────────────>                                                         
            │                                                      │                                                         
            │                                                      │────┐                                                    
            │                                                      │    │ moduleRegistered[_module]                          
            │                                                      │<───┘                                                    
            │                                                      │                                                         
            │                                                      │────┐                                                    
            │                                                      │    │ return <boolean>                                   
            │                                                      │<───┘                                                    
            │                                                      │                                                         
            │                                                      │                                                         
    ╔══════╤╪══════════════════════════════════════════════════════╪════════════════════════════════════════════════════════╗
    ║ ALT  ││ true                                                 │                                                        ║
    ╟──────┘│                                                      │                                                        ║
    ║       │                                                      │────┐                                                   ║
    ║       │                                                      │    │ userApprovals[msg.sender][_module] = _approved    ║
    ║       │                                                      │<───┘                                                   ║
    ║       │                                                      │                                                        ║
    ║       │                                                      │────┐                                                   ║
    ║       │                                                      │    │ emit ModuleApprovalSet                            ║
    ║       │                                                      │<───┘                                                   ║
    ╠═══════╪══════════════════════════════════════════════════════╪════════════════════════════════════════════════════════╣
    ║ [false]                                                      │                                                        ║
    ║       │                        revert                        │                                                        ║
    ║       │ <─────────────────────────────────────────────────────                                                        ║
    ╚═══════╪══════════════════════════════════════════════════════╪════════════════════════════════════════════════════════╝
            User                                          ┌────────┴────────┐                                                
            ┌─┐                                           │ZoraModuleManager│                                                
            ║"│                                           └─────────────────┘                                                
            └┬┘                                                                                                              
            ┌┼┐                                                                                                              
             │                                                                                                               
            ┌┴┐                                                                                                              
   */

    /// @notice Allows a user to set the approval for a given module
    /// @param _module The module to approve
    /// @param _approved A boolean, whether or not to approve a module
    function setApprovalForModule(address _module, bool _approved) public {
        require(moduleRegistered[_module], "ZMM::must be registered module");

        userApprovals[msg.sender][_module] = _approved;

        emit ModuleApprovalSet(msg.sender, _module, _approved);
    }

    /**
       ┌─┐                                                                                                                                                  
       ║"│                                                                                                                                                  
       └┬┘                                                                                                                                                  
       ┌┼┐                                                                                                                                                  
        │                                                            ┌─────────────────┐                                                                    
       ┌┴┐                                                           │ZoraModuleManager│                                                                    
      User                                                           └────────┬────────┘                                                                    
       │ setBatchApprovalForModules(address[] memory _modules, bool _approved)│                                                                             
       │ ─────────────────────────────────────────────────────────────────────>                                                                             
       │                                                                      │                                                                             
       │                                                                      │────┐                                                                        
       │                                                                      │    │ for 0.._modules.length { setApprovalForModule(_modules[i], _approved) }
       │                                                                      │<───┘                                                                        
      User                                                           ┌────────┴────────┐                                                                    
       ┌─┐                                                           │ZoraModuleManager│                                                                    
       ║"│                                                           └─────────────────┘                                                                    
       └┬┘                                                                                                                                                  
       ┌┼┐                                                                                                                                                  
        │                                                                                                                                                   
       ┌┴┐                                                                                                                                                  
    */

    /// @notice Sets approvals for multiple modules at once
    /// @param _modules The list of module addresses to set approvals for
    /// @param _approved A boolean, whether or not to approve the modules
    function setBatchApprovalForModules(address[] memory _modules, bool _approved) public {
        for (uint256 i = 0; i < _modules.length; i++) {
            setApprovalForModule(_modules[i], _approved);
        }
    }

    /**
                                                        ┌─┐      
                                                        ║"│      
                                                        └┬┘      
                                                        ┌┼┐      
   ┌─────────────────┐                                   │       
   │ZoraModuleManager│                                  ┌┴┐      
   └────────┬────────┘                             ZoraRegistrar 
            │      registerModule(address _module)       │       
            │<───────────────────────────────────────────│       
            │                                            │       
            ────┐                                        │       
                │ moduleRegistered[_module] = true       │       
            <───┘                                        │       
            │                                            │       
            ────┐                                        │       
                │ moduleFeeToken.mint(registrar, _module)│       
            <───┘                                        │       
            │                                            │       
            ────┐                                        │       
                │ emit ModuleRegistered                  │       
            <───┘                                        │       
    ┌────────┴────────┐                             ZoraRegistrar 
    │ZoraModuleManager│                                  ┌─┐      
    └─────────────────┘                                  ║"│      
                                                         └┬┘      
                                                         ┌┼┐      
                                                          │       
                                                         ┌┴┐      
    */

    /// @notice Registers a module
    /// @param _module The address of the module
    function registerModule(address _module) public onlyRegistrar {
        require(!moduleRegistered[_module], "ZMM::registerModule module already registered");

        moduleRegistered[_module] = true;
        moduleFeeToken.mint(registrar, _module);

        emit ModuleRegistered(_module);
    }

    /**
                                              ┌─┐      
                                              ║"│      
                                              └┬┘      
                                              ┌┼┐      
    ┌─────────────────┐                        │       
    │ZoraModuleManager│                       ┌┴┐      
    └────────┬────────┘                  ZoraRegistrar 
             │setRegistrar(address _registrar) │       
             │<────────────────────────────────│       
             │                                 │       
             ────┐                             │       
                 │ registrar = _registrar      │       
             <───┘                             │       
             │                                 │       
             ────┐                             │       
                 │ emit RegistrarChanged       │       
             <───┘                             │       
    ┌────────┴────────┐                  ZoraRegistrar 
    │ZoraModuleManager│                       ┌─┐      
    └─────────────────┘                       ║"│      
                                              └┬┘      
                                              ┌┼┐      
                                               │       
                                              ┌┴┐      
    */

    /// @notice Sets the registrar for the ZORA Module Manager
    /// @param _registrar the address of the new registrar
    function setRegistrar(address _registrar) public onlyRegistrar {
        require(_registrar != address(0), "ZMM::setRegistrar must set registrar to non-zero address");
        registrar = _registrar;

        emit RegistrarChanged(_registrar);
    }
}
