// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

/// ------------ IMPORTS ------------

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/// @title Collection Offer Book V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module extension manages offers placed on NFT collections
contract CollectionOfferBookV1 {
    using Counters for Counters.Counter;

    /// @notice The number of created offers
    Counters.Counter public offerCounter;

    struct Offer {
        bool active;
        address buyer;
        uint256 offerAmount;
        uint256 id;
        uint256 prevId;
        uint256 nextId;
    }

    /// ------------ PUBLIC STORAGE ------------

    /// @notice The offer for a given collection + offer ID
    /// @dev NFT address => offer ID
    mapping(address => mapping(uint256 => Offer)) public offers;

    /// @notice The floor offer ID for a given collection
    mapping(address => uint256) public floorOfferId;
    /// @notice The floor offer amount for a given collection
    mapping(address => uint256) public floorOfferAmount;

    /// @notice The ceiling offer ID for a given collection
    mapping(address => uint256) public ceilingOfferId;
    /// @notice The ceiling offer amount for a given collection
    mapping(address => uint256) public ceilingOfferAmount;

    /// ------------ INTERNAL FUNCTIONS ------------

    /// @notice Creates a new offer at the appropriate location in the collection's offer book
    /// @param _offerAmount The amount of ETH offered
    /// @param _buyer The address of the buyer
    /// @return The ID of the created collection offer
    function _addOffer(
        address _collection,
        uint256 _offerAmount,
        address _buyer
    ) internal returns (uint256) {
        offerCounter.increment();
        uint256 _id = offerCounter.current();

        // If first offer for a collection, mark it as both floor and ceiling
        if (_isFirstOffer(_collection)) {
            offers[_collection][_id] = Offer({active: true, buyer: _buyer, offerAmount: _offerAmount, id: _id, prevId: 0, nextId: 0});

            floorOfferId[_collection] = _id;
            floorOfferAmount[_collection] = _offerAmount;

            ceilingOfferId[_collection] = _id;
            ceilingOfferAmount[_collection] = _offerAmount;

            // Else if offer is greater than current ceiling, make it the new ceiling
        } else if (_offerAmount > ceilingOfferAmount[_collection]) {
            uint256 prevCeilingId = ceilingOfferId[_collection];

            offers[_collection][prevCeilingId].nextId = _id;
            offers[_collection][_id] = Offer({active: true, buyer: _buyer, offerAmount: _offerAmount, id: _id, prevId: prevCeilingId, nextId: 0});

            ceilingOfferId[_collection] = _id;
            ceilingOfferAmount[_collection] = _offerAmount;

            // Else if offer is less than or equal to the current floor, make it the new floor
        } else if (_offerAmount <= floorOfferAmount[_collection]) {
            uint256 prevFloorId = floorOfferId[_collection];

            offers[_collection][prevFloorId].prevId = _id;
            offers[_collection][_id] = Offer({active: true, buyer: _buyer, offerAmount: _offerAmount, id: _id, prevId: 0, nextId: prevFloorId});

            floorOfferId[_collection] = _id;
            floorOfferAmount[_collection] = _offerAmount;

            // Else offer is between the floor and ceiling
        } else {
            // Start at the floor offer
            Offer memory offer = offers[_collection][floorOfferId[_collection]];

            // Traverse towards the collection's ceiling, stop when an offer greater than or equal to the current is reached; insert before
            while (offer.offerAmount < _offerAmount) {
                offer = offers[_collection][offer.nextId];
            }

            offers[_collection][_id] = Offer({active: true, buyer: _buyer, offerAmount: _offerAmount, id: _id, prevId: offer.prevId, nextId: offer.id});

            // Update neighboring pointers
            offers[_collection][offer.id].prevId = _id;
            offers[_collection][offer.prevId].nextId = _id;
        }
        return _id;
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
            offers[_collection][_offerId].offerAmount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if the offer is the ceiling and is an amount increase, just update the ceiling
        } else if (_isCeilingIncrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;

            // Else if the offer is the floor and is an amount decrease, just update the floor
        } else if (_isFloorDecrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;

            // Else if the offer (with its updated amount) is still at the correct location, just update its amount
        } else if (_isUpdateInPlace(_collection, _offerId, _newAmount, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;

            // Else the offer requires relocation
        } else {
            Offer memory offer = offers[_collection][_offerId];

            // First connect its neighbors before moving
            _updateOriginalNeighbors(_collection, _offerId, offer.prevId, offer.nextId);

            // If the update is an amount increase, traverse forward until the apt location is found
            if (_increase == true) {
                offer = offers[_collection][offer.nextId];

                while (offer.offerAmount < _newAmount) {
                    offer = offers[_collection][offer.nextId];
                }

                offers[_collection][_offerId].nextId = offer.id;
                offers[_collection][_offerId].prevId = offer.prevId;

                offers[_collection][offer.id].prevId = _offerId;
                offers[_collection][offer.prevId].nextId = _offerId;

                offers[_collection][_offerId].offerAmount = _newAmount;

                // Else the update is a decrease, therefore traverse backwards until the apt location is found
            } else {
                offer = offers[_collection][offer.prevId];

                while (offer.offerAmount >= _newAmount) {
                    offer = offers[_collection][offer.prevId];
                }
                offers[_collection][_offerId].prevId = offer.id;
                offers[_collection][_offerId].nextId = offer.nextId;

                offers[_collection][offer.id].nextId = _offerId;
                offers[_collection][offer.nextId].prevId = _offerId;

                offers[_collection][_offerId].offerAmount = _newAmount;
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
        } else if (_offerId == floorOfferId[_collection]) {
            uint256 newFloorId = offers[_collection][_offerId].nextId;
            uint256 newFloorAmount = offers[_collection][newFloorId].offerAmount;

            offers[_collection][newFloorId].prevId = 0;

            floorOfferId[_collection] = newFloorId;
            floorOfferAmount[_collection] = newFloorAmount;

            delete offers[_collection][_offerId];

            // Else if the offer is the current ceiling, update the collection's ceiling before removing
        } else if (_offerId == ceilingOfferId[_collection]) {
            uint256 newCeilingId = offers[_collection][_offerId].prevId;
            uint256 newCeilingAmount = offers[_collection][newCeilingId].offerAmount;

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
    function _getMatchingOffer(address _collection, uint256 _minAmount) internal view returns (bool, uint256) {
        // If the current ceiling offer is greater than or equal to the seller's minimum, return its id to fill
        if (ceilingOfferAmount[_collection] >= _minAmount) {
            return (true, ceilingOfferId[_collection]);

            // Else traverse backwards from ceiling to floor
        } else {
            Offer memory offer = offers[_collection][ceilingOfferId[_collection]];

            bool matchFound;
            while ((offer.offerAmount >= _minAmount) && (offer.prevId != 0)) {
                offer = offers[_collection][offer.prevId];

                // If the offer is valid to fill, return its id
                if (offer.offerAmount >= _minAmount) {
                    matchFound = true;
                    break;
                }
                // If not, notify the seller there is no matching offer fitting their desired criteria
            }

            return (matchFound, offer.id);
        }
    }

    /// ------------ PRIVATE FUNCTIONS ------------

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

    /// @notice Checks whether an offer to update is an increase of the collection's ceiling offer
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

    /// @notice Checks whether an offer to update is a decrease of the collection's floor offer
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
            ((_increase == true) && (_newAmount <= offers[_collection][nextOffer].offerAmount)) ||
            ((_increase == false) && (_newAmount > offers[_collection][prevOffer].offerAmount));
    }

    /// @notice Connects the pointers of an offer's neighbors
    /// @param _collection The ERC-721 collection
    /// @param _offerId The ID of the offer
    /// @param _prevId The ID of the offer's previous pointer
    /// @param _nextId The ID of the offer's next pointer
    function _updateOriginalNeighbors(
        address _collection,
        uint256 _offerId,
        uint256 _prevId,
        uint256 _nextId
    ) private {
        if (_offerId == floorOfferId[_collection]) {
            offers[_collection][_nextId].prevId = 0;

            floorOfferId[_collection] = _nextId;
            floorOfferAmount[_collection] = offers[_collection][_nextId].offerAmount;
        } else if (_offerId == ceilingOfferId[_collection]) {
            offers[_collection][_prevId].nextId = 0;

            ceilingOfferId[_collection] = _prevId;
            ceilingOfferAmount[_collection] = offers[_collection][_prevId].offerAmount;
        } else {
            offers[_collection][_nextId].prevId = _prevId;
            offers[_collection][_prevId].nextId = _nextId;
        }
    }
}
