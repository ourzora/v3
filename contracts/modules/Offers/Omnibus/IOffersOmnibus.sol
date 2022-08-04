// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {OffersDataStorage} from "./OffersDataStorage.sol";

/// @title IOffersOmnibus
/// @author jgeary
/// @notice Interface for Offers Omnibus
interface IOffersOmnibus {
    function createOfferMinimal(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount
    ) external;

    function createOffer(
        address _tokenContract,
        uint256 _tokenId,
        address _offerCurrency,
        uint256 _offerAmount,
        uint96 _expiry,
        uint16 _findersFeeBps,
        OffersDataStorage.ListingFee memory _listingFee
    ) external;

    function setOfferAmount(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _offerCurrency,
        uint256 _offerAmount
    ) external;

    function cancelOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external;

    function fillOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        uint256 _amount,
        address _currency,
        address _finder
    ) external;
}
