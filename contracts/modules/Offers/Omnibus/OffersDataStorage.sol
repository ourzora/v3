// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract OffersDataStorage {
    struct StoredOffer {
        uint256 amount;
        address maker;
        address currency;
        uint32 features;
        mapping(uint32 => uint256) featureData;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => StoredOffer))) public offers;

    uint256 public offerCount;

    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_EXPIRY = 1 << 5;

    struct ListingFee {
        uint16 listingFeeBps;
        address listingFeeRecipient;
    }

    function _getListingFee(StoredOffer storage offer) internal view returns (ListingFee memory) {
        uint256 data = offer.featureData[FEATURE_MASK_LISTING_FEE];

        return ListingFee({listingFeeBps: uint16(data), listingFeeRecipient: address(uint160(data >> 16))});
    }

    function _setListingFee(
        StoredOffer storage offer,
        uint16 listingFeeBps,
        address listingFeeRecipient
    ) internal {
        offer.features |= FEATURE_MASK_LISTING_FEE;
        offer.featureData[FEATURE_MASK_LISTING_FEE] = listingFeeBps | (uint256(uint160(listingFeeRecipient)) << 16);
    }

    function _getFindersFee(StoredOffer storage offer) internal view returns (uint16) {
        return uint16(offer.featureData[FEATURE_MASK_FINDERS_FEE]);
    }

    function _setFindersFee(StoredOffer storage offer, uint16 _findersFeeBps) internal {
        offer.features |= FEATURE_MASK_FINDERS_FEE;
        offer.featureData[FEATURE_MASK_FINDERS_FEE] = uint256(_findersFeeBps);
    }

    function _getExpiry(StoredOffer storage offer) internal view returns (uint96 expiry) {
        uint256 data = offer.featureData[FEATURE_MASK_EXPIRY];
        expiry = uint96(data);
    }

    function _setExpiry(StoredOffer storage offer, uint96 expiry) internal {
        offer.features |= FEATURE_MASK_EXPIRY;
        offer.featureData[FEATURE_MASK_EXPIRY] = expiry;
    }

    struct FullOffer {
        uint256 amount;
        address maker;
        uint96 expiry;
        uint16 findersFeeBps;
        address currency;
        ListingFee listingFee;
    }

    function _hasFeature(uint32 features, uint32 feature) internal pure returns (bool) {
        return (features & feature) == feature;
    }

    function _getFullOffer(StoredOffer storage offer) internal view returns (FullOffer memory) {
        uint32 features = offer.features;
        FullOffer memory fullOffer;

        if (_hasFeature(features, FEATURE_MASK_LISTING_FEE)) {
            fullOffer.listingFee = _getListingFee(offer);
        }

        if (_hasFeature(features, FEATURE_MASK_FINDERS_FEE)) {
            fullOffer.findersFeeBps = _getFindersFee(offer);
        }

        if (_hasFeature(features, FEATURE_MASK_EXPIRY)) {
            fullOffer.expiry = _getExpiry(offer);
        }

        fullOffer.currency = offer.currency;
        fullOffer.maker = offer.maker;
        fullOffer.amount = offer.amount;

        return fullOffer;
    }
}
