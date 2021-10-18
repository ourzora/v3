// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

interface Ownable {
    function owner() external view returns (address);
}

/// @title Collection Royalty Registry V1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows collection owners to set a collection-wide royalty on all sales in ZORA
contract CollectionRoyaltyRegistryV1 {
    struct CollectionRoyalty {
        address recipient;
        uint8 royaltyPercentage;
    }
    /// @notice The mapping of ERC-721 addresses to their CollectionRoyalty object
    mapping(address => CollectionRoyalty) public collectionRoyalty;

    event CollectionRoyaltyUpdated(address indexed collection, address recipient, uint8 royaltyPercentage);

    /// @notice Sets the royalty specs for a given collection
    /// @param _collectionAddress The address of the ERC-721 contract
    /// @param _recipientAddress The address of the funds recipient for royalty payments
    /// @param _royaltyPercentage The % of sale price to send to the _recipientAddress
    function setRoyalty(
        address _collectionAddress,
        address _recipientAddress,
        uint8 _royaltyPercentage
    ) public {
        address owner = _getCollectionOwner(_collectionAddress);
        require(msg.sender == _collectionAddress || msg.sender == owner, "setRoyalty must be called as owner or collection");

        collectionRoyalty[_collectionAddress] = CollectionRoyalty({recipient: _recipientAddress, royaltyPercentage: _royaltyPercentage});

        emit CollectionRoyaltyUpdated(_collectionAddress, _recipientAddress, _royaltyPercentage);
    }

    function _getCollectionOwner(address _collectionAddress) internal view returns (address) {
        address owner = address(0);

        try Ownable(_collectionAddress).owner() returns (address collectionOwner) {
            owner = collectionOwner;
        } catch {
            // noop
        }

        return owner;
    }
}
