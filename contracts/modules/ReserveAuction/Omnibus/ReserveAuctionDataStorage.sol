// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 5;
uint32 constant FEATURE_MASK_TOKEN_GATE = 1 << 6;
uint32 constant FEATURE_MASK_START_TIME = 1 << 7;
uint32 constant FEATURE_MASK_RECIPIENT_OR_EXPIRY = 1 << 8;
uint32 constant FEATURE_MASK_BUFFER_AND_INCREMENT = 1 << 9;

contract ReserveAuctionDataStorage {
    struct StoredAuction {
        uint256 reservePrice;
        address seller;
        uint64 duration;
        uint32 features;
        mapping(uint32 => uint256) featureData;
    }

    struct OngoingAuction {
        uint96 firstBidTime;
        address highestBidder;
        uint256 highestBid;
    }

    /// @notice The auction for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token id => Auction
    mapping(address => mapping(uint256 => StoredAuction)) public auctionForNFT;
    mapping(address => mapping(uint256 => OngoingAuction)) public ongoingAuctionForNFT;

    struct ListingFee {
        uint16 listingFeeBps;
        address listingFeeRecipient;
    }

    struct TokenGate {
        address token;
        uint256 minAmount;
    }

    struct FindersFee {
        uint16 findersFeeBps;
        address finder;
    }

    function _getListingFee(StoredAuction storage auction) internal view returns (uint16 listingFeeBps, address listingFeeRecipient) {
        uint256 data = auction.featureData[FEATURE_MASK_LISTING_FEE];
        listingFeeBps = uint16(data);
        listingFeeRecipient = address(uint160(data >> 16));
    }

    function _setListingFee(
        StoredAuction storage auction,
        uint16 listingFeeBps,
        address listingFeeRecipient
    ) internal {
        auction.features |= FEATURE_MASK_LISTING_FEE;
        auction.featureData[FEATURE_MASK_LISTING_FEE] = listingFeeBps | (uint256(uint160(listingFeeRecipient)) << 16);
    }

    function _getTokenGate(StoredAuction storage auction) internal view returns (address token, uint256 minAmount) {
        token = address(uint160(auction.featureData[FEATURE_MASK_TOKEN_GATE]));
        minAmount = auction.featureData[FEATURE_MASK_TOKEN_GATE + 1];
    }

    function _setTokenGate(
        StoredAuction storage auction,
        address token,
        uint256 minAmount
    ) internal {
        auction.features |= FEATURE_MASK_TOKEN_GATE;
        auction.featureData[FEATURE_MASK_TOKEN_GATE] = uint256(uint160(token));
        auction.featureData[FEATURE_MASK_TOKEN_GATE + 1] = minAmount;
    }

    function _getFindersFee(StoredAuction storage auction) internal view returns (FindersFee memory) {
        uint256 data = auction.featureData[FEATURE_MASK_FINDERS_FEE];

        return FindersFee({findersFeeBps: uint16(data), finder: address(uint160(data >> 16))});
    }

    function _setFindersFee(
        StoredAuction storage auction,
        uint16 findersFeeBps,
        address finder
    ) internal {
        auction.features |= FEATURE_MASK_FINDERS_FEE;
        auction.featureData[FEATURE_MASK_FINDERS_FEE] = findersFeeBps | (uint256(uint160(finder)) << 16);
    }

    function _getStartTime(StoredAuction storage auction) internal view returns (uint256) {
        return auction.featureData[FEATURE_MASK_START_TIME];
    }

    function _setStartTime(StoredAuction storage auction, uint256 startTime) internal {
        auction.features |= FEATURE_MASK_START_TIME;
        auction.featureData[FEATURE_MASK_START_TIME] = startTime;
    }

    function _getERC20CurrencyWithFallback(StoredAuction storage auction) internal view returns (address) {
        if (!_hasFeature(auction.features, FEATURE_MASK_ERC20_CURRENCY)) {
            return address(0);
        }
        return address(uint160(auction.featureData[FEATURE_MASK_ERC20_CURRENCY]));
    }

    function _setERC20Currency(StoredAuction storage auction, address currency) internal {
        auction.features |= FEATURE_MASK_ERC20_CURRENCY;
        auction.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
    }

    function _getExpiryAndFundsRecipient(StoredAuction storage auction) internal view returns (uint96 expiry, address fundsRecipient) {
        uint256 data = auction.featureData[FEATURE_MASK_RECIPIENT_OR_EXPIRY];
        expiry = uint96(data);
        fundsRecipient = address(uint160(data >> 96));
    }

    function _setExpiryAndFundsRecipient(
        StoredAuction storage auction,
        uint96 expiry,
        address fundsRecipient
    ) internal {
        auction.features |= FEATURE_MASK_RECIPIENT_OR_EXPIRY;
        auction.featureData[FEATURE_MASK_RECIPIENT_OR_EXPIRY] = expiry | (uint256(uint160(fundsRecipient)) << 96);
    }

    function _getBufferAndIncrement(StoredAuction storage auction) internal view returns (uint16 timeBuffer, uint8 percentIncrement) {
        uint256 data = auction.featureData[FEATURE_MASK_BUFFER_AND_INCREMENT];
        timeBuffer = uint16(data);
        percentIncrement = uint8(data >> 16);
    }

    function _setBufferAndIncrement(
        StoredAuction storage auction,
        uint16 timeBuffer,
        uint8 percentIncrement
    ) internal {
        auction.features |= FEATURE_MASK_BUFFER_AND_INCREMENT;
        auction.featureData[FEATURE_MASK_BUFFER_AND_INCREMENT] = uint256(timeBuffer) | (uint256(percentIncrement) << 16);
    }

    struct FullAuction {
        uint256 reservePrice;
        uint256 startTime;
        uint256 tokenGateMinAmount;
        address seller;
        uint96 expiry;
        address currency;
        uint64 duration;
        uint32 features;
        address finder;
        uint16 findersFeeBps;
        uint16 timeBuffer;
        uint8 percentIncrement;
        address fundsRecipient;
        address listingFeeRecipient;
        address tokenGateToken;
        uint16 listingFeeBps;
        OngoingAuction ongoingAuction;
    }

    function _hasFeature(uint32 features, uint32 feature) internal pure returns (bool) {
        return (features & feature) == feature;
    }

    function _getFullAuction(address tokenContract, uint256 tokenId) internal view returns (FullAuction memory) {
        StoredAuction storage auction = auctionForNFT[tokenContract][tokenId];

        uint32 features = auction.features;
        FullAuction memory fullAuction;

        fullAuction.currency = _getERC20CurrencyWithFallback(auction);

        if (_hasFeature(features, FEATURE_MASK_TOKEN_GATE)) {
            (fullAuction.tokenGateToken, fullAuction.tokenGateMinAmount) = _getTokenGate(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_LISTING_FEE)) {
            (fullAuction.listingFeeBps, fullAuction.listingFeeRecipient) = _getListingFee(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_START_TIME)) {
            fullAuction.startTime = _getStartTime(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_FINDERS_FEE)) {
            FindersFee memory findersFee = _getFindersFee(auction);
            fullAuction.findersFeeBps = findersFee.findersFeeBps;
            fullAuction.finder = findersFee.finder;
        }

        if (_hasFeature(features, FEATURE_MASK_ERC20_CURRENCY)) {
            fullAuction.currency = _getERC20CurrencyWithFallback(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_RECIPIENT_OR_EXPIRY)) {
            (uint96 _expiry, address _fundsRecipient) = _getExpiryAndFundsRecipient(auction);
            fullAuction.expiry = _expiry;
            fullAuction.fundsRecipient = _fundsRecipient;
        }

        if (_hasFeature(features, FEATURE_MASK_BUFFER_AND_INCREMENT)) {
            (fullAuction.timeBuffer, fullAuction.percentIncrement) = _getBufferAndIncrement(auction);
        }

        OngoingAuction memory _ongoingAuction = ongoingAuctionForNFT[tokenContract][tokenId];

        fullAuction.seller = auction.seller;
        fullAuction.reservePrice = auction.reservePrice;
        fullAuction.duration = auction.duration;
        fullAuction.features = auction.features;
        fullAuction.ongoingAuction = _ongoingAuction;

        return fullAuction;
    }
}
