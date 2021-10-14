// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

interface Ownable {
    function owner() external view returns (address);
}

contract RoyaltyRegistryV1 {
    struct CollectionRoyalty {
        address recipient;
        uint8 royaltyPercentage;
    }
    mapping(address => CollectionRoyalty) public collectionRoyalty;

    event CollectionRoyaltyUpdated(address indexed collection, address recipient, uint8 royaltyPercentage);

    function setRoyaltyRegistry(
        address _collectionAddress,
        address _recipientAddress,
        uint8 _royaltyPercentage
    ) public {
        address owner = _getCollectionOwner(_collectionAddress);
        require(msg.sender == _collectionAddress || msg.sender == owner, "setRoyaltyRegistry must be called as owner or collection");
        require(_royaltyPercentage <= 10, "setRoyaltyRegistry royalty percentage cannot be greater than 10%");

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
