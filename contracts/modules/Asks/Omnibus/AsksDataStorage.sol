// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract AsksDataStorage {
    struct StoredAsk {
        uint256 price;
        address seller;
        uint32 features;
        mapping(uint32 => uint256) featureData;
    }

    mapping(address => mapping(uint256 => StoredAsk)) public askForNFT;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 5;
    uint32 constant FEATURE_MASK_TOKEN_GATE = 1 << 6;
    uint32 constant FEATURE_MASK_RECIPIENT_OR_EXPIRY = 1 << 7;
    uint32 constant FEATURE_MASK_BUYER = 1 << 8;

    struct ListingFee {
        uint16 listingFeeBps;
        address listingFeeRecipient;
    }

    struct TokenGate {
        address token;
        uint256 minAmount;
    }

    function _getListingFee(StoredAsk storage ask) internal view returns (ListingFee memory) {
        uint256 data = ask.featureData[FEATURE_MASK_LISTING_FEE];

        return ListingFee({listingFeeBps: uint16(data), listingFeeRecipient: address(uint160(data >> 16))});
    }

    function _setListingFee(
        StoredAsk storage ask,
        uint16 listingFeeBps,
        address listingFeeRecipient
    ) internal {
        ask.features |= FEATURE_MASK_LISTING_FEE;
        ask.featureData[FEATURE_MASK_LISTING_FEE] = listingFeeBps | (uint256(uint160(listingFeeRecipient)) << 16);
    }

    function _getFindersFee(StoredAsk storage ask) internal view returns (uint16) {
        return uint16(ask.featureData[FEATURE_MASK_FINDERS_FEE]);
    }

    function _setFindersFee(StoredAsk storage ask, uint16 _findersFeeBps) internal {
        ask.features |= FEATURE_MASK_FINDERS_FEE;
        ask.featureData[FEATURE_MASK_FINDERS_FEE] = uint256(_findersFeeBps);
    }

    function _getAskTokenGate(StoredAsk storage auction) internal view returns (TokenGate memory tokenGate) {
        tokenGate.token = address(uint160(auction.featureData[FEATURE_MASK_TOKEN_GATE]));
        tokenGate.minAmount = auction.featureData[FEATURE_MASK_TOKEN_GATE + 1];
    }

    function _setTokenGate(
        StoredAsk storage ask,
        address token,
        uint256 minAmount
    ) internal {
        ask.features |= FEATURE_MASK_TOKEN_GATE;
        ask.featureData[FEATURE_MASK_TOKEN_GATE] = uint256(uint160(token));
        ask.featureData[FEATURE_MASK_TOKEN_GATE + 1] = minAmount;
    }

    function _getExpiryAndFundsRecipient(StoredAsk storage ask) internal view returns (uint96 expiry, address fundsRecipient) {
        uint256 data = ask.featureData[FEATURE_MASK_RECIPIENT_OR_EXPIRY];
        expiry = uint96(data);
        fundsRecipient = address(uint160(data >> 96));
    }

    function _setExpiryAndFundsRecipient(
        StoredAsk storage ask,
        uint96 expiry,
        address fundsRecipient
    ) internal {
        ask.features |= FEATURE_MASK_RECIPIENT_OR_EXPIRY;
        ask.featureData[FEATURE_MASK_RECIPIENT_OR_EXPIRY] = expiry | (uint256(uint160(fundsRecipient)) << 96);
    }

    function _getERC20CurrencyWithFallback(StoredAsk storage ask) internal view returns (address) {
        if (!_hasFeature(ask.features, FEATURE_MASK_ERC20_CURRENCY)) {
            return address(0);
        }
        return address(uint160(ask.featureData[FEATURE_MASK_ERC20_CURRENCY]));
    }

    function _setERC20Currency(StoredAsk storage ask, address currency) internal {
        ask.features |= FEATURE_MASK_ERC20_CURRENCY;
        ask.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
    }

    function _setETHorERC20Currency(StoredAsk storage ask, address currency) internal {
        // turn off erc20 feature if previous currency was erc20 and new currency is eth
        if (currency == address(0) && _hasFeature(ask.features, FEATURE_MASK_ERC20_CURRENCY)) {
            ask.features &= ~FEATURE_MASK_ERC20_CURRENCY;
        }
        if (currency != address(0)) {
            // turn on erc20 feature if previous currency was eth and new currency is erc20
            if (!_hasFeature(ask.features, FEATURE_MASK_ERC20_CURRENCY)) {
                ask.features |= FEATURE_MASK_ERC20_CURRENCY;
            }
            ask.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
        }
    }

    function _getBuyerWithFallback(StoredAsk storage ask) internal view returns (address) {
        if (!_hasFeature(ask.features, FEATURE_MASK_BUYER)) {
            return address(0);
        }
        return address(uint160(ask.featureData[FEATURE_MASK_BUYER]));
    }

    function _setBuyer(StoredAsk storage ask, address buyer) internal {
        ask.features |= FEATURE_MASK_BUYER;
        ask.featureData[FEATURE_MASK_BUYER] = uint256(uint160(buyer));
    }

    struct FullAsk {
        uint256 price;
        address seller;
        uint96 expiry;
        address sellerFundsRecipient;
        uint16 findersFeeBps;
        address currency;
        address buyer;
        TokenGate tokenGate;
        ListingFee listingFee;
    }

    function _hasFeature(uint32 features, uint32 feature) internal pure returns (bool) {
        return (features & feature) == feature;
    }

    function _getFullAsk(StoredAsk storage ask) internal view returns (FullAsk memory) {
        uint32 features = ask.features;
        FullAsk memory fullAsk;

        fullAsk.currency = _getERC20CurrencyWithFallback(ask);
        fullAsk.buyer = _getBuyerWithFallback(ask);

        if (_hasFeature(features, FEATURE_MASK_TOKEN_GATE)) {
            fullAsk.tokenGate = _getAskTokenGate(ask);
        }

        if (_hasFeature(features, FEATURE_MASK_LISTING_FEE)) {
            fullAsk.listingFee = _getListingFee(ask);
        }

        if (_hasFeature(features, FEATURE_MASK_FINDERS_FEE)) {
            fullAsk.findersFeeBps = _getFindersFee(ask);
        }

        if (_hasFeature(features, FEATURE_MASK_ERC20_CURRENCY)) {
            fullAsk.currency = _getERC20CurrencyWithFallback(ask);
        }

        if (_hasFeature(features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
            (fullAsk.expiry, fullAsk.sellerFundsRecipient) = _getExpiryAndFundsRecipient(ask);
        }

        if (_hasFeature(features, FEATURE_MASK_BUYER)) {
            fullAsk.buyer = _getBuyerWithFallback(ask);
        }

        fullAsk.seller = ask.seller;
        fullAsk.price = ask.price;

        return fullAsk;
    }
}
