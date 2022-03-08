// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ZoraProtocolFeeSettings} from "./auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";

/// @title ZoraModuleManager
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to approve registered modules on ZORA V3
contract ZoraModuleManager {
    /// @notice The EIP-712 type for a signed approval
    /// @dev keccak256("SignedApproval(address module,address user,bool approved,uint256 deadline,uint256 nonce)")
    bytes32 private constant SIGNED_APPROVAL_TYPEHASH = 0x8413132cc7aa5bd2ce1a1b142a3f09e2baeda86addf4f9a5dacd4679f56e7cec;

    /// @notice The EIP-712 domain separator
    bytes32 private immutable EIP_712_DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA")),
                keccak256(bytes("3")),
                _chainID(),
                address(this)
            )
        );

    /// @notice The module fee NFT contract to mint from upon module registration
    ZoraProtocolFeeSettings public immutable moduleFeeToken;

    /// @notice The registrar address that can register modules
    address public registrar;

    /// @notice Mapping of users and modules to approved status
    /// @dev User address => Module address => Approved
    mapping(address => mapping(address => bool)) public userApprovals;

    /// @notice Mapping of modules to registered status
    /// @dev Module address => Registered
    mapping(address => bool) public moduleRegistered;

    /// @notice The signature nonces for 3rd party module approvals
    mapping(address => uint256) public sigNonces;

    /// @notice Ensures only the registrar can register modules
    modifier onlyRegistrar() {
        require(msg.sender == registrar, "ZMM::onlyRegistrar must be registrar");
        _;
    }

    /// @notice Emitted when a user's module approval is updated
    /// @param user The address of the user
    /// @param module The address of the module
    /// @param approved Whether the user added or removed approval
    event ModuleApprovalSet(address indexed user, address indexed module, bool approved);

    /// @notice Emitted when a module is registered
    /// @param module The address of the module
    event ModuleRegistered(address indexed module);

    /// @notice Emitted when the registrar address is updated
    /// @param newRegistrar The address of the new registrar
    event RegistrarChanged(address indexed newRegistrar);

    /// @param _registrar The initial registrar for the manager
    /// @param _feeToken The module fee token contract to mint from upon module registration
    constructor(address _registrar, address _feeToken) {
        require(_registrar != address(0), "ZMM::must set registrar to non-zero address");

        registrar = _registrar;
        moduleFeeToken = ZoraProtocolFeeSettings(_feeToken);
    }

    /// @notice Returns true if the user has approved a given module, false otherwise
    /// @param _user The user to check approvals for
    /// @param _module The module to check approvals for
    /// @return True if the module has been approved by the user, false otherwise
    function isModuleApproved(address _user, address _module) external view returns (bool) {
        return userApprovals[_user][_module];
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,-----------------.
    //        / \            |ZoraModuleManager|
    //      Caller           `--------+--------'
    //        | setApprovalForModule()|
    //        | ---------------------->
    //        |                       |
    //        |                       |----.
    //        |                       |    | set approval for module
    //        |                       |<---'
    //        |                       |
    //        |                       |----.
    //        |                       |    | emit ModuleApprovalSet()
    //        |                       |<---'
    //      Caller           ,--------+--------.
    //        ,-.            |ZoraModuleManager|
    //        `-'            `-----------------'
    //        /|\
    //         |
    //        / \
    /// @notice Allows a user to set the approval for a given module
    /// @param _module The module to approve
    /// @param _approved A boolean, whether or not to approve a module
    function setApprovalForModule(address _module, bool _approved) public {
        _setApprovalForModule(_module, msg.sender, _approved);
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |                  ,-----------------.
    //        / \                 |ZoraModuleManager|
    //      Caller                `--------+--------'
    //        | setBatchApprovalForModule()|
    //        | --------------------------->
    //        |                            |
    //        |                            |
    //        |         _____________________________________________________
    //        |         ! LOOP  /  for each module                           !
    //        |         !______/           |                                 !
    //        |         !                  |----.                            !
    //        |         !                  |    | set approval for module    !
    //        |         !                  |<---'                            !
    //        |         !                  |                                 !
    //        |         !                  |----.                            !
    //        |         !                  |    | emit ModuleApprovalSet()   !
    //        |         !                  |<---'                            !
    //        |         !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //      Caller                ,--------+--------.
    //        ,-.                 |ZoraModuleManager|
    //        `-'                 `-----------------'
    //        /|\
    //         |
    //        / \
    /// @notice Sets approvals for multiple modules at once
    /// @param _modules The list of module addresses to set approvals for
    /// @param _approved A boolean, whether or not to approve the modules
    function setBatchApprovalForModules(address[] memory _modules, bool _approved) public {
        // Store the number of module addresses provided
        uint256 numModules = _modules.length;

        // Loop through each address
        for (uint256 i = 0; i < numModules; ) {
            // Ensure that it's a registered module and set the approval
            _setApprovalForModule(_modules[i], msg.sender, _approved);

            // Cannot overflow as array length cannot exceed uint256 max
            unchecked {
                ++i;
            }
        }
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |                  ,-----------------.
    //        / \                 |ZoraModuleManager|
    //      Caller                `--------+--------'
    //        | setApprovalForModuleBySig()|
    //        | --------------------------->
    //        |                            |
    //        |                            |----.
    //        |                            |    | recover user address from signature
    //        |                            |<---'
    //        |                            |
    //        |                            |----.
    //        |                            |    | set approval for module
    //        |                            |<---'
    //        |                            |
    //        |                            |----.
    //        |                            |    | emit ModuleApprovalSet()
    //        |                            |<---'
    //      Caller                ,--------+--------.
    //        ,-.                 |ZoraModuleManager|
    //        `-'                 `-----------------'
    //        /|\
    //         |
    //        / \
    /// @notice Sets approval for a module given an EIP-712 signature
    /// @param _module The module to approve
    /// @param _user The user to approve the module for
    /// @param _approved A boolean, whether or not to approve a module
    /// @param _deadline The deadline at which point the given signature expires
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function setApprovalForModuleBySig(
        address _module,
        address _user,
        bool _approved,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        require(_deadline == 0 || _deadline >= block.timestamp, "ZMM::setApprovalForModuleBySig deadline expired");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                EIP_712_DOMAIN_SEPARATOR,
                keccak256(abi.encode(SIGNED_APPROVAL_TYPEHASH, _module, _user, _approved, _deadline, sigNonces[_user]++))
            )
        );

        address recoveredAddress = ecrecover(digest, _v, _r, _s);

        require(recoveredAddress != address(0) && recoveredAddress == _user, "ZMM::setApprovalForModuleBySig invalid signature");

        _setApprovalForModule(_module, _user, _approved);
    }

    //         ,-.
    //         `-'
    //         /|\
    //          |               ,-----------------.          ,-----------------------.
    //         / \              |ZoraModuleManager|          |ZoraProtocolFeeSettings|
    //      Registrar           `--------+--------'          `-----------+-----------'
    //          |   registerModule()     |                               |
    //          |----------------------->|                               |
    //          |                        |                               |
    //          |                        ----.                           |
    //          |                            | register module           |
    //          |                        <---'                           |
    //          |                        |                               |
    //          |                        |            mint()             |
    //          |                        |------------------------------>|
    //          |                        |                               |
    //          |                        |                               ----.
    //          |                        |                                   | mint token to registrar
    //          |                        |                               <---'
    //          |                        |                               |
    //          |                        ----.                           |
    //          |                            | emit ModuleRegistered()   |
    //          |                        <---'                           |
    //      Registrar           ,--------+--------.          ,-----------+-----------.
    //         ,-.              |ZoraModuleManager|          |ZoraProtocolFeeSettings|
    //         `-'              `-----------------'          `-----------------------'
    //         /|\
    //          |
    //         / \
    /// @notice Registers a module
    /// @param _module The address of the module
    function registerModule(address _module) public onlyRegistrar {
        require(!moduleRegistered[_module], "ZMM::registerModule module already registered");

        moduleRegistered[_module] = true;
        moduleFeeToken.mint(registrar, _module);

        emit ModuleRegistered(_module);
    }

    //         ,-.
    //         `-'
    //         /|\
    //          |               ,-----------------.
    //         / \              |ZoraModuleManager|
    //      Registrar           `--------+--------'
    //          |    setRegistrar()      |
    //          |----------------------->|
    //          |                        |
    //          |                        ----.
    //          |                            | set registrar
    //          |                        <---'
    //          |                        |
    //          |                        ----.
    //          |                            | emit RegistrarChanged()
    //          |                        <---'
    //      Registrar           ,--------+--------.
    //         ,-.              |ZoraModuleManager|
    //         `-'              `-----------------'
    //         /|\
    //          |
    //         / \
    /// @notice Sets the registrar for the ZORA Module Manager
    /// @param _registrar the address of the new registrar
    function setRegistrar(address _registrar) public onlyRegistrar {
        require(_registrar != address(0), "ZMM::setRegistrar must set registrar to non-zero address");
        registrar = _registrar;

        emit RegistrarChanged(_registrar);
    }

    /// @notice Updates a module approval for a user
    /// @param _module The address of the module
    /// @param _user The address of the user
    /// @param _approved Whether the user is adding or removing approval
    function _setApprovalForModule(
        address _module,
        address _user,
        bool _approved
    ) private {
        require(moduleRegistered[_module], "ZMM::must be registered module");

        userApprovals[_user][_module] = _approved;

        emit ModuleApprovalSet(msg.sender, _module, _approved);
    }

    /// @notice The EIP-155 chain id
    function _chainID() private view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }
}
