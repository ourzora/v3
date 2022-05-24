// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract AuctionDataStorage {
    /// @notice The auction for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token id => Auction
    mapping(address => mapping(uint256 => StoredAuction)) public auctionForNFT;
    mapping(address => mapping(uint256 => OngoingAuction)) public ongoingAuctionForNFT;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 5;
    uint32 constant FEATURE_MASK_TOKEN_GATE = 1 << 6;
    uint32 constant FEATURE_MASK_SET_START_TIME = 1 << 7;
    uint32 constant FEATURE_MASK_FUNDS_RECIPIENT = 1 << 8;

    struct StoredAuction {
        address seller; // 160
        uint96 reservePrice; // 256
        uint80 duration; // 80
        uint32 features; // 192
        uint16 findersFeeBps; // 218
        mapping(uint32 => uint256) featureData;
    }

    struct OngoingAuction {
        uint96 firstBidTime;
        address highestBidder;
        uint96 highestBid;
    }

    // 2 slots
    struct ListingFee {
        uint16 listingFeeBps;
        address listingFeeRecipient;
    }

    struct AuctionTokenGate {
        address token;
        uint256 minAmount;
    }

    function _getListingFee(StoredAuction storage auction) internal view returns (ListingFee memory) {
        uint256 data = auction.featureData[FEATURE_MASK_LISTING_FEE];

        return ListingFee({listingFeeBps: uint16(data), listingFeeRecipient: address(uint160(data >> 16))});
    }

    function _setListingFee(
        StoredAuction storage auction,
        uint16 listingFeeBps,
        address listingFeeRecipient
    ) internal {
        auction.features |= FEATURE_MASK_LISTING_FEE;
        auction.featureData[FEATURE_MASK_LISTING_FEE] = uint16(listingFeeBps) | (uint256(uint160(listingFeeRecipient)) << 16);
    }

    function _getAuctionTokenGate(StoredAuction storage auction) internal view returns (AuctionTokenGate memory tokenGate) {
        tokenGate.token = address(uint160(auction.featureData[FEATURE_MASK_TOKEN_GATE]));
        tokenGate.minAmount = auction.featureData[FEATURE_MASK_TOKEN_GATE + 1];
    }

    function _setSellerFundsRecipient(StoredAuction storage auction, address _sellerFundsRecipient) internal {
        auction.features |= FEATURE_MASK_FUNDS_RECIPIENT;
        auction.featureData[FEATURE_MASK_FUNDS_RECIPIENT] = uint256(uint160(_sellerFundsRecipient));
    }

    function _getSellerFundsRecipient(StoredAuction storage auction) internal view returns (address) {
        return address(uint160(auction.featureData[FEATURE_MASK_FUNDS_RECIPIENT]));
    }

    function _setAuctionTokenGate(
        StoredAuction storage auction,
        address token,
        uint256 minAmount
    ) internal {
        auction.features |= FEATURE_MASK_TOKEN_GATE;
        auction.featureData[FEATURE_MASK_TOKEN_GATE] = uint256(uint160(token));
        auction.featureData[FEATURE_MASK_TOKEN_GATE + 1] = minAmount;
    }

    function _getStartTime(StoredAuction storage auction) internal view returns (uint256) {
        return auction.featureData[FEATURE_MASK_SET_START_TIME];
    }

    function _setStartTime(StoredAuction storage auction, uint256 startTime) internal {
        auction.features |= FEATURE_MASK_SET_START_TIME;
        auction.featureData[FEATURE_MASK_SET_START_TIME] = startTime;
    }

    function _getERC20CurrencyWithFallback(StoredAuction storage auction) internal view returns (address) {
        if (!_hasFeature(auction.features, FEATURE_MASK_ERC20_CURRENCY)) {
            return address(0x0);
        }
        return address(uint160(auction.featureData[FEATURE_MASK_ERC20_CURRENCY]));
    }

    function _setERC20Currency(StoredAuction storage auction, address currency) internal {
        auction.features |= FEATURE_MASK_ERC20_CURRENCY;
        auction.featureData[FEATURE_MASK_ERC20_CURRENCY] = uint256(uint160(currency));
    }

    // // force an auction to start at a specific time
    // uint256 startTime;

    // // erc20
    // address currency;

    struct FullAuction {
        address seller;
        uint96 reservePrice;
        uint80 duration;
        uint256 startTime;
        uint32 features;
        uint256 findersFeeBps;
        address currency;
        OngoingAuction ongoingAuction;
        ListingFee listingFee;
        AuctionTokenGate tokenGate;
    }

    function _hasFeature(uint32 features, uint32 feature) internal pure returns (bool) {
        return (features & feature) == features;
    }

    function _getFullAuction(StoredAuction storage auction) internal view returns (FullAuction memory) {
        uint32 features = auction.features;
        FullAuction memory fullAuction;

        fullAuction.currency = _getERC20CurrencyWithFallback(auction);

        if (_hasFeature(features, FEATURE_MASK_TOKEN_GATE)) {
            fullAuction.tokenGate = _getAuctionTokenGate(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_LISTING_FEE)) {
            fullAuction.listingFee = _getListingFee(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_SET_START_TIME)) {
            fullAuction.startTime = _getStartTime(auction);
        }

        if (_hasFeature(features, FEATURE_MASK_ERC20_CURRENCY)) {
            fullAuction.currency = _getERC20CurrencyWithFallback(auction);
        }

        fullAuction.seller = auction.seller;
        fullAuction.reservePrice = auction.reservePrice;
        fullAuction.duration = auction.duration;
        fullAuction.features = auction.features;

        return fullAuction;
    }
}
