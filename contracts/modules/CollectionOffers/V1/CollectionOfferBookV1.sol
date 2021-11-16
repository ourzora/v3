// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/// @title Collection Offer Book V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module extension manages offers placed on NFT collections
contract CollectionOfferBookV1 {
    using Counters for Counters.Counter;

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

    function _updateOffer(
        address _collection,
        uint256 _offerId,
        uint256 _newAmount,
        bool _increase
    ) internal {
        if (_isOnlyOffer(_collection, _offerId)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;
        } else if (_isCeilingIncrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
            ceilingOfferAmount[_collection] = _newAmount;
        } else if (_isFloorDecrease(_collection, _offerId, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
            floorOfferAmount[_collection] = _newAmount;
        } else if (_isUpdateInPlace(_collection, _offerId, _newAmount, _increase)) {
            offers[_collection][_offerId].offerAmount = _newAmount;
        } else {
            Offer memory offer = offers[_collection][_offerId];

            // Update original neighbors before updating offer location
            _updateOriginalNeighbors(_collection, _offerId, offer.prevId, offer.nextId);

            // If update is an increase, traverse forward until apt location is found
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

                // Else offer is a decrease, therefore traverse backwards until apt location is found
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

    function _getMatchingOffer(address _collection, uint256 _minAmount) internal view returns (bool, uint256) {
        // If the current ceiling offer fits the seller's minimum, return its id to fill
        if (ceilingOfferAmount[_collection] >= _minAmount) {
            return (true, ceilingOfferId[_collection]);

            // Else traverse backwards from ceiling to floor
        } else {
            Offer memory offer = offers[_collection][ceilingOfferId[_collection]];

            bool matchFound;
            while ((offer.offerAmount >= _minAmount) && (offer.prevId != 0)) {
                offer = offers[_collection][offer.prevId];

                // If a valid offer to fill exists, return its id
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

    function _isFirstOffer(address _collection) private view returns (bool) {
        return (ceilingOfferId[_collection] == 0) && (floorOfferId[_collection] == 0);
    }

    function _isOnlyOffer(address _collection, uint256 _offerId) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]) && (_offerId == ceilingOfferId[_collection]);
    }

    function _isCeilingIncrease(
        address _collection,
        uint256 _offerId,
        bool _increase
    ) private view returns (bool) {
        return (_offerId == ceilingOfferId[_collection]) && (_increase == true);
    }

    function _isFloorDecrease(
        address _collection,
        uint256 _offerId,
        bool _increase
    ) private view returns (bool) {
        return (_offerId == floorOfferId[_collection]) && (_increase == false);
    }

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

            floorOfferId[_collection] = _prevId;
            floorOfferAmount[_collection] = offers[_collection][_prevId].offerAmount;
        } else {
            offers[_collection][_nextId].prevId = _prevId;
            offers[_collection][_prevId].nextId = _nextId;
        }
    }
}
