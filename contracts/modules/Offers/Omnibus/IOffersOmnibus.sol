// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {OffersDataStorage} from "./OffersDataStorage.sol";

/// @title IOffersOmnibus
/// @author jgeary
/// @notice Interface for Offers Omnibus
interface IOffersOmnibus {
    error INSUFFICIENT_ALLOWANCE();

    error MODULE_NOT_APPROVED();

    error NO_ZERO_OFFERS();

    error MSG_VALUE_NEQ_ZERO_WITH_OTHER_CURRENCY();

    error INSUFFICIENT_BALANCE();

    error MSG_VALUE_NEQ_OFFER_AMOUNT();

    error INVALID_FEES();

    error INVALID_EXPIRY();

    error CALLER_NOT_MAKER();

    error SAME_OFFER();

    error INACTIVE_OFFER();

    error NOT_TOKEN_OWNER();

    error INCORRECT_CURRENCY_OR_AMOUNT();

    error TOKEN_TRANSFER_AMOUNT_INCORRECT();

    error OFFER_EXPIRED();

    function createOfferMinimal(address _tokenContract, uint256 _tokenId) external payable returns (uint256);

    function createOffer(
        address _tokenContract,
        uint256 _tokenId,
        address _offerCurrency,
        uint256 _offerAmount,
        uint96 _expiry,
        uint16 _findersFeeBps,
        OffersDataStorage.ListingFee memory _listingFee
    ) external payable returns (uint256);

    function setOfferAmount(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId,
        address _offerCurrency,
        uint256 _offerAmount
    ) external payable;

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

    function getFullOffer(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _offerId
    ) external view returns (OffersDataStorage.FullOffer memory);
}
