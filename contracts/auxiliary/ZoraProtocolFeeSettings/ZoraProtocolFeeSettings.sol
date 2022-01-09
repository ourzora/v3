// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/// @title ZoraProtocolFeeSettings
/// @author tbtstl <t@zora.co>
/// @notice This contract allows an optional fee percentage and recipient to be set for individual ZORA modules
contract ZoraProtocolFeeSettings is ERC721Enumerable {
    struct FeeSetting {
        uint16 feeBps;
        address feeRecipient;
    }

    address public owner;
    address public minter;
    mapping(uint256 => address) public tokenIdToModule;
    mapping(address => uint256) public moduleToTokenId;
    mapping(address => FeeSetting) public moduleFeeSetting;

    event OwnerUpdated(address indexed newOwner);
    event ProtocolFeeUpdated(address indexed module, address feeRecipient, uint16 feeBps);

    // Only allow the module fee owner to access the function
    modifier onlyModuleOwner(address _module) {
        uint256 tokenId = moduleToTokenId[_module];
        require(ownerOf(tokenId) == msg.sender, "onlyModuleOwner");

        _;
    }

    constructor() ERC721("ZORA Module Fee Switch", "ZORF") {
        _setOwner(msg.sender);
    }

    /// @notice Initialize the Protocol Fee Settings
    /// @param _minter The address that can mint new NFTs (expected ZoraProposalManager address)
    function init(address _minter) external {
        require(msg.sender == owner, "init only owner");
        require(minter == address(0), "init already initialized");

        minter = _minter;
    }

    /// @notice Mint a new protocol fee setting for a module
    /// @param _to, the address to send the protocol fee setting token to
    /// @param _module, the module for which the minted token will represent
    /// TODO: derive token ID from module address to save double storage, and provide a pure func to convert easily
    function mint(address _to, address _module) external returns (uint256) {
        require(msg.sender == minter, "mint onlyMinter");

        uint256 tokenId = totalSupply();

        _mint(_to, tokenId);

        tokenIdToModule[tokenId] = _module;
        moduleToTokenId[_module] = tokenId;

        return tokenId;
    }

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

    /// @notice Sets the owner of the contract
    /// @param _owner the new owner
    function setOwner(address _owner) external {
        require(msg.sender == owner, "setOwner onlyOwner");
        _setOwner(_owner);
    }

    /// @notice Computes the fee for a given uint256 amount
    /// @param _module The module to compute the fee for
    /// @param _amount The amount to compute the fee for
    /// @return amount to be paid out to the fee recipient
    function getFeeAmount(address _module, uint256 _amount) external view returns (uint256) {
        return (_amount * moduleFeeSetting[_module].feeBps) / 10000;
    }

    function _setOwner(address _owner) private {
        owner = _owner;

        emit OwnerUpdated(_owner);
    }
}
