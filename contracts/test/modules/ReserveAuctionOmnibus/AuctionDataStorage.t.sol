// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AuctionDataStorage} from "../../../modules/ReserveAuctionOmnibus/AuctionDataStorage.sol";
import {VM} from "../../utils/VM.sol";

contract StorageTestBaseFull is AuctionDataStorage {
    function newAuction(address tokenContract, uint256 tokenId) public {
        StoredAuction storage auction = auctionForNFT[tokenContract][tokenId];
        auction.seller = address(0x11);
        auction.reservePrice = 0.4 ether;
        auction.duration = 1000;
        _setERC20Currency(auction, address(0x123));
        _setAuctionTokenGate(auction, address(0x111), 0.1 ether);
        _setStartTime(auction, 1000);
    }

    function getExpectedActiveFeatures() public returns (uint32) {
        return FEATURE_MASK_ERC20_CURRENCY | FEATURE_MASK_TOKEN_GATE | FEATURE_MASK_SET_START_TIME;
    }

    function hasFeature(uint32 features, uint32 feature) public returns (bool) {
        return _hasFeature(features, feature);
    }

    function getFullAuction(address tokenContract, uint256 tokenId) public returns (FullAuction memory) {
        return _getFullAuction(auctionForNFT[tokenContract][tokenId]);
    }
}

contract StorageTestBaseMinimal is AuctionDataStorage {
    function newAuction(address tokenContract, uint256 tokenId) public {
        StoredAuction storage auction = auctionForNFT[tokenContract][tokenId];
        auction.seller = address(0x11);
        auction.reservePrice = 0.4 ether;
        auction.duration = 1000;
    }

    function hasFeature(uint32 features, uint32 feature) public returns (bool) {
        return _hasFeature(features, feature);
    }

    function getFullAuction(address tokenContract, uint256 tokenId) public returns (FullAuction memory) {
        return _getFullAuction(auctionForNFT[tokenContract][tokenId]);
    }
}

/// @title
/// @notice
contract AuctionDataStorageTest is DSTest {
    VM internal vm;

    function test_AuctionStorageMinimalInit() public {
        StorageTestBaseMinimal dataStorage = new StorageTestBaseMinimal();
        dataStorage.newAuction(address(0x11), 21);
        AuctionDataStorage.FullAuction memory auction = dataStorage.getFullAuction(address(0x11), 21);
        assertEq(auction.seller, address(0x11), "seller wrong");
        assertEq(auction.reservePrice, 0.4 ether, "reserve price wrong");
        assertEq(auction.duration, 1000, "duration wrong");
        assertEq(auction.startTime, 0, "starttime wrong");
        assertEq(auction.features, 0, "features wrong");
        assertEq(auction.findersFeeBps, 0, "findersfeebps wrong");
        assertEq(auction.currency, address(0x0));
        assertEq(auction.ongoingAuction.firstBidTime, 0);
        assertEq(auction.ongoingAuction.highestBidder, address(0x0));
        assertEq(auction.ongoingAuction.highestBid, 0);
        assertEq(auction.listingFee.listingFeeBps, 0, "listingfee wrong");
        assertEq(auction.listingFee.listingFeeRecipient, address(0x0), "listingfee recipient wrong");
        assertEq(auction.tokenGate.token, address(0x0), "tokengate wrong");
        assertEq(auction.tokenGate.minAmount, 0, "tokengate wrong");
        assertEq(address(1), address(2));
    }

    function test_AuctionStorageInit() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newAuction(address(0x11), 21);
        AuctionDataStorage.FullAuction memory auction = dataStorage.getFullAuction(address(0x11), 21);
        assertEq(auction.seller, address(0x11), "seller wrong");
        assertEq(auction.reservePrice, 0.4 ether, "reserve price wrong");
        assertEq(auction.duration, 1000, "duration wrong");
        assertEq(auction.startTime, 1000, "starttime wrong");
        assertEq(auction.features, dataStorage.getExpectedActiveFeatures(), "features wrong");
        assertEq(auction.findersFeeBps, 0, "findersfeebps wrong");
        assertEq(auction.currency, address(0x123), "currency wrong");
        assertEq(auction.ongoingAuction.firstBidTime, 0);
        assertEq(auction.ongoingAuction.highestBidder, address(0x0));
        assertEq(auction.ongoingAuction.highestBid, 0);
        assertEq(auction.listingFee.listingFeeBps, 0, "listingfee wrong");
        assertEq(auction.listingFee.listingFeeRecipient, address(0x0), "listingfee recipient wrong");
        assertEq(auction.tokenGate.token, address(0x111), "tokengate wrong");
        assertEq(auction.tokenGate.minAmount, 0.1 ether, "tokengate wrong");
    }
}
