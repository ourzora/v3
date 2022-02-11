// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------

/// @title Collection Offer Book V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module extension manages offers placed on ERC-721 collections
contract CollectionOfferBookV1 {
    /// @notice The number of offers placed
    uint32 public offerCount;

    /// @notice The metadata of a collection offer
    /// @param maker The address of the maker that placed the offer
    /// @param id The ID of the offer
    /// @param prevId The ID of the previous offer in its collection's offer book
    /// @param nextId The ID of the next offer in its collection's offer book
    /// @param amount The amount of ETH offered
    struct Offer {
        address maker;
        uint32 id;
        uint32 prevId;
        uint32 nextId;
        uint256 amount;
    }

    /// ------------ PUBLIC STORAGE ------------

    /// @notice The metadata for a given collection offer
    /// @dev ERC-721 token address => Offer ID => Offer
    mapping(address => mapping(uint256 => Offer)) public offers;

    /// @notice The floor offer ID for a given collection
    /// @dev ERC-721 token address => Floor offer ID
    mapping(address => uint256) public floorOfferId;

    /// @notice The floor offer amount for a given collection
    /// @dev ERC-721 token address => Floor offer amount
    mapping(address => uint256) public floorOfferAmount;

    /// @notice The ceiling offer ID for a given collection
    /// @dev ERC-721 token address => Ceiling offer ID
    mapping(address => uint256) public ceilingOfferId;

    /// @notice The ceiling offer amount for a given collection
    /// @dev ERC-721 token address => Ceiling offer amount
    mapping(address => uint256) public ceilingOfferAmount;

    /// ------------ INTERNAL FUNCTIONS ------------

    /// @notice Creates and places a new offer in its collection's offer book
    /// @param _amount The amount of ETH offered
    /// @param _maker The address of the maker
    /// @return The ID of the created collection offer
    function _addOffer(
        address _collection,
        uint256 _amount,
        address _maker
    ) internal returns (uint256) {
        uint256 _offerCount;
        unchecked {
            _offerCount = ++offerCount;
        }

        // If first offer for a collection, mark as both floor and ceiling
        if (_isFirstOffer(_collection)) {
            offers[_collection][_offerCount] = Offer({maker: _maker, amount: _amount, id: uint32(_offerCount), prevId: 0, nextId: 0});

            floorOfferId[_collection] = _offerCount;
            floorOfferAmount[_collection] = _amount;

            ceilingOfferId[_collection] = _offerCount;
            ceilingOfferAmount[_collection] = _amount;

            // Else if offer is greater than current ceiling, mark as new ceiling
        } else if (_isNewCeiling(_collection, _amount)) {
            uint256 prevCeilingId = ceilingOfferId[_collection];

            offers[_collection][prevCeilingId].nextId = uint32(_offerCount);
            offers[_collection][_offerCount] = Offer({
                maker: _maker,
                amount: _amount,
                id: uint32(_offerCount),
                prevId: uint32(prevCeilingId),
                nextId: 0
            });

            ceilingOfferId[_collection] = _offerCount;
            ceilingOfferAmount[_collection] = _amount;

            // Else if offer is less than or equal to current floor, mark as new floor
        } else if (_isNewFloor(_collection, _amount)) {
            uint256 prevFloorId = floorOfferId[_collection];

            offers[_collection][prevFloorId].prevId = uint32(_offerCount);
            offers[_collection][_offerCount] = Offer({
                maker: _maker,
                amount: _amount,
                id: uint32(_offerCount),
                prevId: 0,
                nextId: uint32(prevFloorId)
            });

            floorOfferId[_collection] = _offerCount;
            floorOfferAmount[_collection] = _amount;

            // Else offer is between floor and ceiling --
        } else {
            // Start at floor
            Offer memory offer = offers[_collection][floorOfferId[_collection]];

            // Traverse towards ceiling; stop when an offer greater than or equal to new offer is reached
            while ((offer.amount < _amount) && (offer.nextId != 0)) {
                offer = offers[_collection][offer.nextId];
            }

            // Insert new offer before (time priority)
            offers[_collection][_offerCount] = Offer({
                maker: _maker,
                amount: _amount,
                id: uint32(_offerCount),
                prevId: offer.prevId,
                nextId: offer.id
            });

            // Update neighboring pointers
            offers[_collection][offer.id].prevId = uint32(_offerCount);
            offers[_collection][offer.prevId].nextId = uint32(_offerCount);
        }

        return _offerCount;
    }

    /// @notice Updates an offer and (if needed) its location relative to other offers in the collection
    /// @param _offer The metadata of the offer to update
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _newAmount The new offer amount
    /// @param _increase Whether the update is an amount increase or decrease
    function _updateOffer(
        Offer storage _offer,
        address _collection,
        uint256 _offerId,
        uint256 _newAmount,
        bool _increase
    ) internal {
        // If offer to update is only offer for its collection --
        if (_isOnlyOffer(_collection, _offerId)) {
            // Update offer
            _offer.amount = _newAmount;
            // Update collection floor
            floorOfferAmount[_collection] = _newAmount;
            // Update collection ceiling
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if offer does not require relocation --
        } else if (_isUpdateInPlace(_collection, _offerId, _newAmount, _increase)) {
            if (_isCeilingOffer(_collection, _offerId)) {
                // Update offer
                _offer.amount = _newAmount;
                // Update collection ceiling
                ceilingOfferAmount[_collection] = _newAmount;
            } else if (_isFloorOffer(_collection, _offerId)) {
                // Update offer
                _offer.amount = _newAmount;
                // Update collection floor
                floorOfferAmount[_collection] = _newAmount;
            } else {
                // Update offer
                _offer.amount = _newAmount;
            }

            // Else if offer is new ceiling --
        } else if (_isNewCeiling(_collection, _newAmount)) {
            // Get previous neighbors
            uint256 prevId = _offer.prevId;
            uint256 nextId = _offer.nextId;

            // Update previous neighbors
            _connectNeighbors(_collection, _offerId, prevId, nextId);

            // Update previous ceiling
            uint256 prevCeilingId = ceilingOfferId[_collection];
            offers[_collection][prevCeilingId].nextId = uint32(_offerId);

            // Update offer to be new ceiling
            _offer.prevId = uint32(prevCeilingId);
            _offer.nextId = 0;
            _offer.amount = _newAmount;

            // Update collection ceiling
            ceilingOfferId[_collection] = _offerId;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if offer is new floor --
        } else if (_isNewFloor(_collection, _newAmount)) {
            // Get previous neighbors
            uint256 prevId = _offer.prevId;
            uint256 nextId = _offer.nextId;

            // Update previous neighbors
            _connectNeighbors(_collection, _offerId, prevId, nextId);

            // Update previous floor
            uint256 prevFloorId = floorOfferId[_collection];
            offers[_collection][prevFloorId].prevId = uint32(_offerId);

            // Update offer to be new floor
            _offer.nextId = uint32(prevFloorId);
            _offer.prevId = 0;
            _offer.amount = _newAmount;

            // Update collection floor
            floorOfferId[_collection] = _offerId;
            floorOfferAmount[_collection] = _newAmount;

            // Else offer requires relocation between floor and ceiling --
        } else {
            // Update previous neighbors
            _connectNeighbors(_collection, _offerId, _offer.prevId, _offer.nextId);

            // If update is increase --
            if (_increase) {
                // Traverse forward until insert location is found
                _insertIncreasedOffer(_collection, _offerId, _offer.nextId, _newAmount);
                // Else update is decrease --
            } else {
                // Traverse backward until insert location is found
                _insertDecreasedOffer(_collection, _offerId, _offer.prevId, _newAmount);
            }
        }
    }

    /// @notice Removes an offer from its collection's offer book
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    function _removeOffer(address _collection, uint256 _offerId) internal {
        // If offer is only one for collection, remove all associated data
        if (_isOnlyOffer(_collection, _offerId)) {
            delete floorOfferId[_collection];
            delete floorOfferAmount[_collection];
            delete ceilingOfferId[_collection];
            delete ceilingOfferAmount[_collection];
            delete offers[_collection][_offerId];

            // Else if the offer is the current floor, update the collection's floor before removing
        } else if (_isFloorOffer(_collection, _offerId)) {
            uint256 newFloorId = offers[_collection][_offerId].nextId;
            uint256 newFloorAmount = offers[_collection][newFloorId].amount;

            offers[_collection][newFloorId].prevId = 0;

            floorOfferId[_collection] = newFloorId;
            floorOfferAmount[_collection] = newFloorAmount;

            delete offers[_collection][_offerId];

            // Else if the offer is the current ceiling, update the collection's ceiling before removing
        } else if (_isCeilingOffer(_collection, _offerId)) {
            uint256 newCeilingId = offers[_collection][_offerId].prevId;
            uint256 newCeilingAmount = offers[_collection][newCeilingId].amount;

            offers[_collection][newCeilingId].nextId = 0;

            ceilingOfferId[_collection] = newCeilingId;
            ceilingOfferAmount[_collection] = newCeilingAmount;

            delete offers[_collection][_offerId];

            // Else offer is in middle, so update its previous and next neighboring pointers before removing
        } else {
            Offer memory offer = offers[_collection][_offerId];

            offers[_collection][offer.nextId].prevId = uint32(offer.prevId);
            offers[_collection][offer.prevId].nextId = uint32(offer.nextId);

            delete offers[_collection][_offerId];
        }
    }

    /// @notice Finds a collection offer to fill
    /// @param _collection The address of the ERC-721 collection
    /// @param _minAmount The minimum offer amount valid to match
    function _getMatchingOffer(address _collection, uint256 _minAmount) internal view returns (uint256) {
        // If current ceiling offer is greater than or equal to maker's minimum, return its id to fill
        if (ceilingOfferAmount[_collection] >= _minAmount) {
            return ceilingOfferId[_collection];
            // Else return no offer found
        } else {
            return 0;
        }
    }

    /// ------------ PRIVATE FUNCTIONS ------------

    /// @notice Checks whether any offers exist for a collection
    /// @param _collection The address of the ERC-721 collection
    function _isFirstOffer(address _collection) private view returns (bool) {
        return (ceilingOfferId[_collection] == 0) && (floorOfferId[_collection] == 0);
    }

    /// @notice Checks whether a given offer is the only one for a collection
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isOnlyOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]) && (_offerId == ceilingOfferId[_collection]);
    }

    /// @notice Checks whether a given offer is the collection ceiling
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isCeilingOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == ceilingOfferId[_collection]);
    }

    /// @notice Checks whether a given offer is the collection floor
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isFloorOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]);
    }

    /// @notice Checks whether an offer is greater than the collection ceiling
    /// @param _collection The address of the ERC-721 collection
    /// @param _amount The offer amount
    function _isNewCeiling(address _collection, uint256 _amount) private view returns (bool) {
        return (_amount > ceilingOfferAmount[_collection]);
    }

    /// @notice Checks whether an offer is less than or equal to the collection floor
    /// @param _collection The address of the ERC-721 collection
    /// @param _amount The offer amount
    function _isNewFloor(address _collection, uint256 _amount) private view returns (bool) {
        return (_amount <= floorOfferAmount[_collection]);
    }

    /// @notice Checks whether an offer can be updated without relocation
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _newAmount The new offer amount
    /// @param _increase Whether the update is an amount increase or decrease
    function _isUpdateInPlace(
        address _collection,
        uint256 _offerId,
        uint256 _newAmount,
        bool _increase
    ) private view returns (bool) {
        uint256 nextOffer = offers[_collection][_offerId].nextId;
        uint256 prevOffer = offers[_collection][_offerId].prevId;
        return
            ((_increase == true) && (_newAmount <= offers[_collection][nextOffer].amount)) ||
            ((_increase == false) && (_newAmount > offers[_collection][prevOffer].amount));
    }

    /// @notice Connects the pointers of an offer's neighbors
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _prevId The ID of the offer's previous pointer
    /// @param _nextId The ID of the offer's next pointer
    function _connectNeighbors(
        address _collection,
        uint256 _offerId,
        uint256 _prevId,
        uint256 _nextId
    ) private {
        // If offer is floor --
        if (_offerId == floorOfferId[_collection]) {
            // Mark next as new floor
            offers[_collection][_nextId].prevId = 0;
            // Update floor data
            floorOfferId[_collection] = _nextId;
            floorOfferAmount[_collection] = offers[_collection][_nextId].amount;

            // Else if offer is ceiling --
        } else if (_offerId == ceilingOfferId[_collection]) {
            // Mark previous as new ceiling
            offers[_collection][_prevId].nextId = 0;
            // Update ceiling data
            ceilingOfferId[_collection] = _prevId;
            ceilingOfferAmount[_collection] = offers[_collection][_prevId].amount;

            // Else offer is in middle --
        } else {
            // Update neighbor pointers
            offers[_collection][_nextId].prevId = uint32(_prevId);
            offers[_collection][_prevId].nextId = uint32(_nextId);
        }
    }

    /// @notice Updates the location of an increased offer
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer to relocate
    /// @param _nextId The next ID of the offer to relocate
    /// @param _newAmount The new offer amount
    function _insertIncreasedOffer(
        address _collection,
        uint256 _offerId,
        uint256 _nextId,
        uint256 _newAmount
    ) private {
        Offer memory offer = offers[_collection][_nextId];

        // Traverse forward until the apt location is found
        while ((offer.amount < _newAmount) && (offer.nextId != 0)) {
            offer = offers[_collection][offer.nextId];
        }

        // Update offer pointers
        offers[_collection][_offerId].nextId = uint32(offer.id);
        offers[_collection][_offerId].prevId = uint32(offer.prevId);

        // Update neighbor pointers
        offers[_collection][offer.id].prevId = uint32(_offerId);
        offers[_collection][offer.prevId].nextId = uint32(_offerId);

        // Update offer amount
        offers[_collection][_offerId].amount = _newAmount;
    }

    /// @notice Updates the location of a decreased offer
    /// @param _collection The address of the ERC-721 collection
    /// @param _offerId The ID of the offer to relocate
    /// @param _prevId The previous ID of the offer to relocate
    /// @param _newAmount The new offer amount
    function _insertDecreasedOffer(
        address _collection,
        uint256 _offerId,
        uint256 _prevId,
        uint256 _newAmount
    ) private {
        Offer memory offer = offers[_collection][_prevId];

        // Traverse backwards until apt location is found
        while ((offer.amount >= _newAmount) && (offer.prevId != 0)) {
            offer = offers[_collection][offer.prevId];
        }

        // Update offer pointers
        offers[_collection][_offerId].prevId = uint32(offer.id);
        offers[_collection][_offerId].nextId = uint32(offer.nextId);

        // Update neighbor pointers
        offers[_collection][offer.id].nextId = uint32(_offerId);
        offers[_collection][offer.nextId].prevId = uint32(_offerId);

        // Update offer amount
        offers[_collection][_offerId].amount = _newAmount;
    }
}
