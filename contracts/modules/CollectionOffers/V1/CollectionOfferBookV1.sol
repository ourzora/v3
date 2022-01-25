// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// ------------ IMPORTS ------------ ///

/// @title Collection Offer Book V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module extension manages offers placed on ERC-721 collections
contract CollectionOfferBookV1 {
    /// @notice The number of offers placed
    uint256 public offerCount;

    /// @notice The metadata of a collection offer
    /// @param seller The address of the seller that placed the offer
    /// @param amount The amount of ETH offered
    /// @param id The ID of the offer
    /// @param prevId The ID of the previous offer in its collection's offer book
    /// @param nextId The ID of the next offer in its collection's offer book
    struct Offer {
        address seller;
        uint256 amount;
        uint256 id;
        uint256 prevId;
        uint256 nextId;
    }

    /// ------------ PUBLIC STORAGE ------------ ///

    /// @notice The metadata for a given collection offer
    /// @dev ERC-721 token address => ERC-721 token ID => Offer ID => Offer
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

    /// @notice The finders fee bps (if overriden) for a given collection offer
    /// @notice ERC-721 token address => Offer ID => Finders Fee BPS
    mapping(address => mapping(uint256 => uint16)) public findersFeeOverrides;

    /// ------------ INTERNAL FUNCTIONS ------------ ///

    /// @notice Creates and places a new offer in its collection's offer book
    /// @param _offerAmount The amount of ETH offered
    /// @param _seller The address of the seller
    /// @return The ID of the created collection offer
    function _addOffer(
        address _collection,
        uint256 _offerAmount,
        address _seller
    ) internal returns (uint256) {
        offerCount++;

        // If its the first offer for a collection, mark it as both floor and ceiling
        if (_isFirstOffer(_collection)) {
            offers[_collection][offerCount] = Offer({seller: _seller, amount: _offerAmount, id: offerCount, prevId: 0, nextId: 0});

            floorOfferId[_collection] = offerCount;
            floorOfferAmount[_collection] = _offerAmount;

            ceilingOfferId[_collection] = offerCount;
            ceilingOfferAmount[_collection] = _offerAmount;

            // Else if offer is greater than current ceiling, make it the new ceiling
        } else if (_isNewCeiling(_collection, _offerAmount)) {
            uint256 prevCeilingId = ceilingOfferId[_collection];

            offers[_collection][prevCeilingId].nextId = offerCount;
            offers[_collection][offerCount] = Offer({seller: _seller, amount: _offerAmount, id: offerCount, prevId: prevCeilingId, nextId: 0});

            ceilingOfferId[_collection] = offerCount;
            ceilingOfferAmount[_collection] = _offerAmount;

            // Else if offer is less than or equal to the current floor, make it the new floor
        } else if (_isNewFloor(_collection, _offerAmount)) {
            uint256 prevFloorId = floorOfferId[_collection];

            offers[_collection][prevFloorId].prevId = offerCount;
            offers[_collection][offerCount] = Offer({seller: _seller, amount: _offerAmount, id: offerCount, prevId: 0, nextId: prevFloorId});

            floorOfferId[_collection] = offerCount;
            floorOfferAmount[_collection] = _offerAmount;

            // Else offer is between the floor and ceiling --
        } else {
            // Start at the floor
            Offer memory offer = offers[_collection][floorOfferId[_collection]];

            // Traverse towards the ceiling, stop when an offer greater than or equal to (time priority) is reached; insert before
            while ((offer.amount < _offerAmount) && (offer.nextId != 0)) {
                offer = offers[_collection][offer.nextId];
            }

            offers[_collection][offerCount] = Offer({seller: _seller, amount: _offerAmount, id: offerCount, prevId: offer.prevId, nextId: offer.id});

            // Update neighboring pointers
            offers[_collection][offer.id].prevId = offerCount;
            offers[_collection][offer.prevId].nextId = offerCount;
        }

        return offerCount;
    }

    /// @notice Updates an offer and (if needed) its location relative to other offers in the collection
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _newAmount The new offer amount
    /// @param _increase Whether the update is an amount increase or decrease
    function _updateOffer(
        address _collection,
        uint256 _offerId,
        uint256 _newAmount,
        bool _increase
    ) internal {
        // If the offer to update is the only offer in the collection, update the floor and ceiling amounts as well
        if (_isOnlyOffer(_collection, _offerId)) {
            offers[_collection][_offerId].amount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if the offer is the ceiling and the update is an increase, just update the ceiling
        } else if (_isCeilingIncrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].amount = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if the offer is the floor and the update is a decrease, just update the floor
        } else if (_isFloorDecrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].amount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;

            // Else if the offer is still at the correct location, just update its amount
        } else if (_isUpdateInPlace(_collection, _offerId, _newAmount, _increase)) {
            offers[_collection][_offerId].amount = _newAmount;

            // Else if the offer is the new ceiling --
        } else if (_isNewCeiling(_collection, _newAmount)) {
            uint256 prevId = offers[_collection][_offerId].prevId;
            uint256 nextId = offers[_collection][_offerId].nextId;

            // Update previous neighbors
            _connectPreviousNeighbors(_collection, _offerId, prevId, nextId);

            // Update previous ceiling
            uint256 prevCeilingId = ceilingOfferId[_collection];
            offers[_collection][prevCeilingId].nextId = _offerId;

            // Update offer as new ceiling
            offers[_collection][_offerId].prevId = prevCeilingId;
            offers[_collection][_offerId].nextId = 0;
            offers[_collection][_offerId].amount = _newAmount;

            // Update collection ceiling
            ceilingOfferId[_collection] = _offerId;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if the offer is the new floor --
        } else if (_isNewFloor(_collection, _newAmount)) {
            uint256 prevId = offers[_collection][_offerId].prevId;
            uint256 nextId = offers[_collection][_offerId].nextId;

            // Update previous neighbors
            _connectPreviousNeighbors(_collection, _offerId, prevId, nextId);

            // Update previous floor
            uint256 prevFloorId = floorOfferId[_collection];
            offers[_collection][prevFloorId].prevId = _offerId;

            // Update offer as new floor
            offers[_collection][_offerId].nextId = prevFloorId;
            offers[_collection][_offerId].prevId = 0;
            offers[_collection][_offerId].amount = _newAmount;

            // Update collection floor
            floorOfferId[_collection] = _offerId;
            floorOfferAmount[_collection] = _newAmount;

            // Else move the offer to the apt middle location
        } else {
            Offer memory offer = offers[_collection][_offerId];

            // Update previous neighbors
            _connectPreviousNeighbors(_collection, _offerId, offer.prevId, offer.nextId);

            if (_increase) {
                // Traverse forward until the apt location is found
                _insertIncreasedOffer(offer, _collection, _offerId, _newAmount);
            } else {
                // Traverse backward until the apt location is found
                _insertDecreasedOffer(offer, _collection, _offerId, _newAmount);
            }
        }
    }

    /// @notice Removes an offer from its collection's offer book
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    function _removeOffer(address _collection, uint256 _offerId) internal {
        // If the offer to remove is the only one for its collection, remove it and reset associated collection data stored
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

            offers[_collection][offer.nextId].prevId = offer.prevId;
            offers[_collection][offer.prevId].nextId = offer.nextId;

            delete offers[_collection][_offerId];
        }
    }

    /// @notice Finds a collection offer to fill
    /// @param _collection The ERC-721 collection
    /// @param _minAmount The minimum offer amount valid to match
    function _getMatchingOffer(address _collection, uint256 _minAmount) internal view returns (uint256) {
        // If current ceiling offer is greater than or equal to seller's minimum, return its id to fill
        if (ceilingOfferAmount[_collection] >= _minAmount) {
            return ceilingOfferId[_collection];
            // Else notify seller that no offer fitting their specified minimum exists
        } else {
            return 0;
        }
    }

    /// ------------ PRIVATE FUNCTIONS ------------ ///

    /// @notice Checks whether any offers exist for a collection
    /// @param _collection The ERC-721 collection
    function _isFirstOffer(address _collection) private view returns (bool) {
        return (ceilingOfferId[_collection] == 0) && (floorOfferId[_collection] == 0);
    }

    /// @notice Checks whether a given offer is the only one for a collection
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isOnlyOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]) && (_offerId == ceilingOfferId[_collection]);
    }

    /// @notice Checks whether a given offer is the collection ceiling
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isCeilingOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == ceilingOfferId[_collection]);
    }

    /// @notice Checks whether a given offer is the collection floor
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    function _isFloorOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]);
    }

    /// @notice Checks whether an offer is greater than the collection ceiling
    /// @param _collection The ERC-721 collection
    /// @param _offerAmount The offer amount
    function _isNewCeiling(address _collection, uint256 _offerAmount) private view returns (bool) {
        return (_offerAmount > ceilingOfferAmount[_collection]);
    }

    /// @notice Checks whether an offer is less than or equal to the collection floor
    /// @param _collection The ERC-721 collection
    /// @param _offerAmount The offer amount
    function _isNewFloor(address _collection, uint256 _offerAmount) private view returns (bool) {
        return (_offerAmount <= floorOfferAmount[_collection]);
    }

    /// @notice Checks whether an offer to increase is the collection ceiling
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _increase Whether the update is an amount increase or decrease
    function _isCeilingIncrease(
        address _collection,
        uint256 _offerId,
        bool _increase
    ) private view returns (bool) {
        return (_offerId == ceilingOfferId[_collection]) && (_increase == true);
    }

    /// @notice Checks whether an offer to decrease is the collection floor
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _increase Whether the update is an amount increase or decrease
    function _isFloorDecrease(
        address _collection,
        uint256 _offerId,
        bool _increase
    ) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]) && (_increase == false);
    }

    /// @notice Checks whether an offer can be updated without relocation
    /// @param _collection The ERC-721 collection
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
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _prevId The ID of the offer's previous pointer
    /// @param _nextId The ID of the offer's next pointer
    function _connectPreviousNeighbors(
        address _collection,
        uint256 _offerId,
        uint256 _prevId,
        uint256 _nextId
    ) private {
        if (_offerId == floorOfferId[_collection]) {
            offers[_collection][_nextId].prevId = 0;

            floorOfferId[_collection] = _nextId;
            floorOfferAmount[_collection] = offers[_collection][_nextId].amount;
        } else if (_offerId == ceilingOfferId[_collection]) {
            offers[_collection][_prevId].nextId = 0;

            ceilingOfferId[_collection] = _prevId;
            ceilingOfferAmount[_collection] = offers[_collection][_prevId].amount;
        } else {
            offers[_collection][_nextId].prevId = _prevId;
            offers[_collection][_prevId].nextId = _nextId;
        }
    }

    /// @notice Updates the location of an increased offer
    /// @param offer The Offer associated with _offerId
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _newAmount The new offer amount
    function _insertIncreasedOffer(
        Offer memory offer,
        address _collection,
        uint256 _offerId,
        uint256 _newAmount
    ) private {
        offer = offers[_collection][offer.nextId];

        // Traverse forward until the apt location is found
        while ((offer.amount < _newAmount) && (offer.nextId != 0)) {
            offer = offers[_collection][offer.nextId];
        }

        // Update offer pointers
        offers[_collection][_offerId].nextId = offer.id;
        offers[_collection][_offerId].prevId = offer.prevId;

        // Update neighbor pointers
        offers[_collection][offer.id].prevId = _offerId;
        offers[_collection][offer.prevId].nextId = _offerId;

        // Update offer amount
        offers[_collection][_offerId].amount = _newAmount;
    }

    /// @notice Updates the location of a decreased offer
    /// @param offer The Offer associated with _offerId
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _newAmount The new offer amount
    function _insertDecreasedOffer(
        Offer memory offer,
        address _collection,
        uint256 _offerId,
        uint256 _newAmount
    ) private {
        offer = offers[_collection][offer.prevId];

        // Traverse backwards until the apt location is found
        while ((offer.amount >= _newAmount) && (offer.prevId != 0)) {
            offer = offers[_collection][offer.prevId];
        }

        // Update offer pointers
        offers[_collection][_offerId].prevId = offer.id;
        offers[_collection][_offerId].nextId = offer.nextId;

        // Update neighbor pointers
        offers[_collection][offer.id].nextId = _offerId;
        offers[_collection][offer.nextId].prevId = _offerId;

        // Update offer amount
        offers[_collection][_offerId].amount = _newAmount;
    }
}
