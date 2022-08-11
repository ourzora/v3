// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract OffersDataStorage {
    struct StoredOffer {
        uint256 amount;
        address maker;
        uint32 features;
        mapping(uint32 => uint256) featureData;
    }

    mapping(address => mapping(uint256 => mapping(uint256 => StoredOffer))) public offers;

    uint256 public offerCount;

    mapping(address => mapping(uint256 => uint256[])) public offersForNFT;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_EXPIRY = 1 << 5;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 6;

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

    function _getERC20CurrencyWithFallback(StoredOffer storage offer) internal view returns (address) {
        if (!_hasFeature(offer.features, FEATURE_MASK_ERC20_CURRENCY)) {
            return address(0);
        }
        return address(uint160(offer.featureData[FEATURE_MASK_ERC20_CURRENCY]));
    }

    function _setERC20Currency(StoredOffer storage offer, address currency) internal {
        offer.features |= FEATURE_MASK_ERC20_CURRENCY;
        offer.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
    }

    function _setETHorERC20Currency(StoredOffer storage offer, address currency) internal {
        // turn off erc20 feature if previous currency was erc20 and new currency is eth
        if (currency == address(0) && _hasFeature(offer.features, FEATURE_MASK_ERC20_CURRENCY)) {
            offer.features &= ~FEATURE_MASK_ERC20_CURRENCY;
        }
        if (currency != address(0)) {
            // turn on erc20 feature if previous currency was eth and new currency is erc20
            if (!_hasFeature(offer.features, FEATURE_MASK_ERC20_CURRENCY)) {
                offer.features |= FEATURE_MASK_ERC20_CURRENCY;
            }
            offer.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
        }
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

        fullOffer.currency = _getERC20CurrencyWithFallback(offer);
        fullOffer.maker = offer.maker;
        fullOffer.amount = offer.amount;

        return fullOffer;
    }
}
