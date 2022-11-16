// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {ReserveAuctionDataStorage, FEATURE_MASK_LISTING_FEE, FEATURE_MASK_FINDERS_FEE, FEATURE_MASK_ERC20_CURRENCY, FEATURE_MASK_TOKEN_GATE, FEATURE_MASK_START_TIME, FEATURE_MASK_RECIPIENT_OR_EXPIRY} from "../../../../modules/ReserveAuction/Omnibus/ReserveAuctionDataStorage.sol";
import {VM} from "../../../utils/VM.sol";

contract StorageTestBaseFull is ReserveAuctionDataStorage {
    function newAuction(address tokenContract, uint256 tokenId) public {
        StoredAuction storage auction = auctionForNFT[tokenContract][tokenId];
        auction.seller = address(0x001);
        auction.reservePrice = 0.4 ether;
        auction.duration = 2 hours;
        _setERC20Currency(auction, address(0x002));
        _setTokenGate(auction, address(0x003), 0.1 ether);
        _setStartTime(auction, uint96(block.timestamp) + 1 days);
        _setListingFee(auction, 1, address(0x004));
        _setFindersFee(auction, 2, address(0));
        _setExpiryAndFundsRecipient(auction, uint96(block.timestamp) + 2 days, address(0x005));
    }

    function getExpectedActiveFeatures() public returns (uint32) {
        return
            FEATURE_MASK_LISTING_FEE |
            FEATURE_MASK_FINDERS_FEE |
            FEATURE_MASK_ERC20_CURRENCY |
            FEATURE_MASK_TOKEN_GATE |
            FEATURE_MASK_START_TIME |
            FEATURE_MASK_RECIPIENT_OR_EXPIRY;
    }

    function hasFeature(uint32 features, uint32 feature) public returns (bool) {
        return _hasFeature(features, feature);
    }

    function getFullAuction(address tokenContract, uint256 tokenId) public returns (FullAuction memory) {
        return _getFullAuction(tokenContract, tokenId);
    }
}

contract StorageTestBaseMinimal is ReserveAuctionDataStorage {
    function newAuction(address tokenContract, uint256 tokenId) public {
        StoredAuction storage auction = auctionForNFT[tokenContract][tokenId];
        auction.seller = address(0x001);
        auction.reservePrice = 0.4 ether;
        auction.duration = 1000;
    }

    function hasFeature(uint32 features, uint32 feature) public returns (bool) {
        return _hasFeature(features, feature);
    }

    function getFullAuction(address tokenContract, uint256 tokenId) public returns (FullAuction memory) {
        return _getFullAuction(tokenContract, tokenId);
    }
}

/// @title
/// @notice
contract AuctionDataStorageTest is DSTest {
    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 5;
    uint32 constant FEATURE_MASK_TOKEN_GATE = 1 << 6;
    uint32 constant FEATURE_MASK_START_TIME = 1 << 7;
    uint32 constant FEATURE_MASK_RECIPIENT_OR_EXPIRY = 1 << 8;

    VM internal vm;

    function test_AuctionStorageMinimalInit() public {
        StorageTestBaseMinimal dataStorage = new StorageTestBaseMinimal();
        dataStorage.newAuction(address(0x11), 21);
        ReserveAuctionDataStorage.FullAuction memory auction = dataStorage.getFullAuction(address(0x11), 21);
        assertEq(auction.seller, address(0x001), "seller wrong");
        assertEq(auction.reservePrice, 0.4 ether, "reserve price wrong");
        assertEq(auction.duration, 1000, "duration wrong");
        assertEq(auction.startTime, 0, "starttime wrong");
        assertEq(auction.features, 0, "features wrong");
        assertEq(auction.findersFeeBps, 0, "findersfeebps wrong");
        assertEq(auction.currency, address(0x0));
        assertEq(auction.ongoingAuction.firstBidTime, 0);
        assertEq(auction.ongoingAuction.highestBidder, address(0x0));
        assertEq(auction.ongoingAuction.highestBid, 0);
        assertEq(auction.listingFeeBps, 0, "listingfee wrong");
        assertEq(auction.listingFeeRecipient, address(0x0), "listingfee recipient wrong");
        assertEq(auction.tokenGateToken, address(0x0), "tokengate wrong");
        assertEq(auction.tokenGateMinAmount, 0, "tokengate wrong");
        assertEq(auction.expiry, 0, "expiry wrong");
        assertEq(auction.fundsRecipient, address(0), "funds recipient wrong");
    }

    function test_AuctionStorageInit() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newAuction(address(0x12), 21);
        ReserveAuctionDataStorage.FullAuction memory auction = dataStorage.getFullAuction(address(0x12), 21);
        assertEq(auction.seller, address(0x001), "seller wrong");
        assertEq(auction.reservePrice, 0.4 ether, "reserve price wrong");
        assertEq(auction.duration, 2 hours, "duration wrong");
        assertEq(auction.startTime, block.timestamp + 1 days, "starttime wrong");
        assertEq(auction.features, dataStorage.getExpectedActiveFeatures(), "features wrong");
        assertEq(auction.findersFeeBps, 2, "findersfeebps wrong");
        assertEq(auction.currency, address(0x002), "currency wrong");
        assertEq(auction.ongoingAuction.firstBidTime, 0);
        assertEq(auction.ongoingAuction.highestBidder, address(0x0));
        assertEq(auction.ongoingAuction.highestBid, 0);
        assertEq(auction.listingFeeBps, 1, "listingfee wrong");
        assertEq(auction.listingFeeRecipient, address(0x004), "listingfee recipient wrong");
        assertEq(auction.tokenGateToken, address(0x003), "tokengate wrong");
        assertEq(auction.tokenGateMinAmount, 0.1 ether, "tokengate wrong");
        assertEq(auction.expiry, uint96(block.timestamp) + 2 days, "expiry wrong");
        assertEq(auction.fundsRecipient, address(0x005), "funds recipient wrong");
    }
}
