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
    struct FeeSetting {
        uint16 feeBps;
        address feeRecipient;
    }

    address public metadata;
    address public owner;
    address public minter;
    mapping(address => FeeSetting) public moduleFeeSetting;

    event MetadataUpdated(address indexed newMetadata);
    event OwnerUpdated(address indexed newOwner);
    event ProtocolFeeUpdated(address indexed module, address feeRecipient, uint16 feeBps);

    // Only allow the module fee owner to access the function
    modifier onlyModuleOwner(address _module) {
        uint256 tokenId = moduleToTokenId(_module);
        require(ownerOf(tokenId) == msg.sender, "onlyModuleOwner");

        _;
    }

    constructor() ERC721("ZORA Module Fee Switch", "ZORF") {
        _setOwner(msg.sender);
    }

    /// @notice Initialize the Protocol Fee Settings
    /// @param _minter The address that can mint new NFTs (expected ZoraProposalManager address)
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
    /// @param _to, the address to send the protocol fee setting token to
    /// @param _module, the module for which the minted token will represent
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
    /// @notice Sets fee parameters for ZORA protocol.
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
    /// @param _owner the new owner
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
    function setMetadata(address _metadata) external {
        require(msg.sender == owner, "setMetadata onlyOwner");
        _setMetadata(_metadata);
    }

    /// @notice Computes the fee for a given uint256 amount
    /// @param _module The module to compute the fee for
    /// @param _amount The amount to compute the fee for
    /// @return amount to be paid out to the fee recipient
    function getFeeAmount(address _module, uint256 _amount) external view returns (uint256) {
        return (_amount * moduleFeeSetting[_module].feeBps) / 10000;
    }

    /// @notice returns the module address for a given token ID
    /// @param _tokenId The token ID
    function tokenIdToModule(uint256 _tokenId) public pure returns (address) {
        return address(uint160(_tokenId));
    }

    /// @notice returns the token ID for a given module
    /// @dev we don't worry about losing the top 20 bytes when going from uint256 -> uint160 since we know token ID must have derived from an address
    /// @param _module The module address
    function moduleToTokenId(address _module) public pure returns (uint256) {
        return uint256(uint160(_module));
    }

    function _setOwner(address _owner) private {
        owner = _owner;

        emit OwnerUpdated(_owner);
    }

    function _setMetadata(address _metadata) private {
        metadata = _metadata;

        emit MetadataUpdated(_metadata);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        require(metadata != address(0), "ERC721Metadata: no metadata address");

        return IERC721TokenURI(metadata).tokenURI(tokenId);
    }
}
