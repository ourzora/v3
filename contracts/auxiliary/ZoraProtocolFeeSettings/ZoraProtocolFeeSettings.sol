// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IERC721TokenURI {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/// @title ZoraProtocolFeeSettings
/// @author tbtstl <t@zora.co>
/// @notice This contract allows an optional fee percentage and recipient to be set for individual ZORA modules
contract ZoraProtocolFeeSettings is ERC721 {
    /// @notice The address of the contract metadata
    address public metadata;
    /// @notice The address of the contract owner
    address public owner;
    /// @notice The address of the ZORA Module Manager
    address public minter;

    /// @notice The metadata of a module fee setting
    /// @param feeBps The basis points fee
    /// @param feeRecipient The recipient of the fee
    struct FeeSetting {
        uint16 feeBps;
        address feeRecipient;
    }

    /// @notice Mapping of modules to fee settings
    /// @dev Module address => FeeSetting
    mapping(address => FeeSetting) public moduleFeeSetting;

    /// @notice Ensures only the owner of a module fee NFT can set its fee
    /// @param _module The address of the module
    modifier onlyModuleOwner(address _module) {
        uint256 tokenId = moduleToTokenId(_module);
        require(ownerOf(tokenId) == msg.sender, "onlyModuleOwner");
        _;
    }

    /// @notice Emitted when the fee for a module is updated
    /// @param module The address of the module
    /// @param feeRecipient The address of the fee recipient
    /// @param feeBps The basis points of the fee
    event ProtocolFeeUpdated(address indexed module, address feeRecipient, uint16 feeBps);

    /// @notice Emitted when the contract metadata is updated
    /// @param newMetadata The address of the new metadata
    event MetadataUpdated(address indexed newMetadata);

    /// @notice Emitted when the contract owner is updated
    /// @param newOwner The address of the new owner
    event OwnerUpdated(address indexed newOwner);

    constructor() ERC721("ZORA Module Fee Switch", "ZORF") {
        _setOwner(msg.sender);
    }

    /// @notice Initialize the Protocol Fee Settings
    /// @param _minter The address that can mint new NFTs (expected ZoraModuleManager address)
    function init(address _minter, address _metadata) external {
        require(msg.sender == owner, "init only owner");
        require(minter == address(0), "init already initialized");

        minter = _minter;
        metadata = _metadata;
    }

    //        ,-.
    //        `-'
    //        /|\
    //         |             ,-----------------------.
    //        / \            |ZoraProtocolFeeSettings|
    //      Minter           `-----------+-----------'
    //        |          mint()          |
    //        | ------------------------>|
    //        |                          |
    //        |                          ----.
    //        |                              | derive token ID from module address
    //        |                          <---'
    //        |                          |
    //        |                          ----.
    //        |                              | mint token to given address
    //        |                          <---'
    //        |                          |
    //        |     return token ID      |
    //        | <------------------------|
    //      Minter           ,-----------+-----------.
    //        ,-.            |ZoraProtocolFeeSettings|
    //        `-'            `-----------------------'
    //        /|\
    //         |
    //        / \
    /// @notice Mint a new protocol fee setting for a module
    /// @param _to The address to send the protocol fee setting token to
    /// @param _module The module for which the minted token will represent
    function mint(address _to, address _module) external returns (uint256) {
        require(msg.sender == minter, "mint onlyMinter");
        uint256 tokenId = moduleToTokenId(_module);
        _mint(_to, tokenId);

        return tokenId;
    }

    //          ,-.
    //          `-'
    //          /|\
    //           |                ,-----------------------.
    //          / \               |ZoraProtocolFeeSettings|
    //      ModuleOwner           `-----------+-----------'
    //           |      setFeeParams()        |
    //           |--------------------------->|
    //           |                            |
    //           |                            ----.
    //           |                                | set fee parameters
    //           |                            <---'
    //           |                            |
    //           |                            ----.
    //           |                                | emit ProtocolFeeUpdated()
    //           |                            <---'
    //      ModuleOwner           ,-----------+-----------.
    //          ,-.               |ZoraProtocolFeeSettings|
    //          `-'               `-----------------------'
    //          /|\
    //           |
    //          / \
    /// @notice Sets fee parameters for a module fee NFT
    /// @param _module The module to apply the fee settings to
    /// @param _feeRecipient The fee recipient address to send fees to
    /// @param _feeBps The bps of transaction value to send to the fee recipient
    function setFeeParams(
        address _module,
        address _feeRecipient,
        uint16 _feeBps
    ) external onlyModuleOwner(_module) {
        require(_feeBps <= 10000, "setFeeParams must set fee <= 100%");
        require(_feeRecipient != address(0) || _feeBps == 0, "setFeeParams fee recipient cannot be 0 address if fee is greater than 0");

        moduleFeeSetting[_module] = FeeSetting(_feeBps, _feeRecipient);

        emit ProtocolFeeUpdated(_module, _feeRecipient, _feeBps);
    }

    //       ,-.
    //       `-'
    //       /|\
    //        |             ,-----------------------.
    //       / \            |ZoraProtocolFeeSettings|
    //      Owner           `-----------+-----------'
    //        |       setOwner()        |
    //        |------------------------>|
    //        |                         |
    //        |                         ----.
    //        |                             | set owner
    //        |                         <---'
    //        |                         |
    //        |                         ----.
    //        |                             | emit OwnerUpdated()
    //        |                         <---'
    //      Owner           ,-----------+-----------.
    //       ,-.            |ZoraProtocolFeeSettings|
    //       `-'            `-----------------------'
    //       /|\
    //        |
    //       / \
    /// @notice Sets the owner of the contract
    /// @param _owner The address of the owner
    function setOwner(address _owner) external {
        require(msg.sender == owner, "setOwner onlyOwner");
        _setOwner(_owner);
    }

    //       ,-.
    //       `-'
    //       /|\
    //        |             ,-----------------------.
    //       / \            |ZoraProtocolFeeSettings|
    //      Owner           `-----------+-----------'
    //        |     setMetadata()       |
    //        |------------------------>|
    //        |                         |
    //        |                         ----.
    //        |                             | set metadata
    //        |                         <---'
    //        |                         |
    //        |                         ----.
    //        |                             | emit MetadataUpdated()
    //        |                         <---'
    //      Owner           ,-----------+-----------.
    //       ,-.            |ZoraProtocolFeeSettings|
    //       `-'            `-----------------------'
    //       /|\
    //        |
    //       / \
    /// @notice Sets the metadata of the contract
    /// @param _metadata The address of the metadata
    function setMetadata(address _metadata) external {
        require(msg.sender == owner, "setMetadata onlyOwner");
        _setMetadata(_metadata);
    }

    /// @notice Computes the fee for a given uint256 amount
    /// @param _module The module to compute the fee for
    /// @param _amount The amount to compute the fee for
    /// @return The amount to be paid out to the fee recipient
    function getFeeAmount(address _module, uint256 _amount) external view returns (uint256) {
        return (_amount * moduleFeeSetting[_module].feeBps) / 10000;
    }

    /// @notice Returns the module address for a given token ID
    /// @param _tokenId The token ID
    /// @return The module address
    function tokenIdToModule(uint256 _tokenId) public pure returns (address) {
        return address(uint160(_tokenId));
    }

    /// @notice Returns the token ID for a given module
    /// @dev We don't worry about losing the top 20 bytes when going from uint256 -> uint160 since we know token ID must have derived from an address
    /// @param _module The module address
    /// @return The token ID
    function moduleToTokenId(address _module) public pure returns (uint256) {
        return uint256(uint160(_module));
    }

    /// @notice Returns the token URI for a given token ID
    /// @param _tokenId The token ID
    /// @return The token URI
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        require(metadata != address(0), "ERC721Metadata: no metadata address");

        return IERC721TokenURI(metadata).tokenURI(_tokenId);
    }

    /// @notice Sets the contract metadata in `setMetadata`
    /// @param _metadata The address of the metadata
    function _setMetadata(address _metadata) private {
        metadata = _metadata;

        emit MetadataUpdated(_metadata);
    }

    /// @notice Sets the contract owner in `setOwner`
    /// @param _owner The address of the owner
    function _setOwner(address _owner) private {
        owner = _owner;

        emit OwnerUpdated(_owner);
    }
}
