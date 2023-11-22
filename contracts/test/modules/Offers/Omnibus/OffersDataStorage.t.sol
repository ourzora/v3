// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {OffersDataStorage} from "../../../../modules/Offers/Omnibus/OffersDataStorage.sol";
import {VM} from "../../../utils/VM.sol";

contract StorageTestBaseFull is OffersDataStorage {
    uint256 offerCounter;

    function newOffer(address tokenContract, uint256 tokenId) public {
        StoredOffer storage offer = offers[tokenContract][tokenId][++offerCounter];
        offer.maker = address(0x111);
        offer.amount = 0.4 ether;
        _setETHorERC20Currency(offer, address(0x113));
        _setListingFee(offer, 1, address(0x115));
        _setFindersFee(offer, 2);
        _setExpiry(offer, uint96(block.timestamp + 1_000));
    }

    function getExpectedActiveFeatures() public pure returns (uint32) {
        return FEATURE_MASK_LISTING_FEE | FEATURE_MASK_FINDERS_FEE | FEATURE_MASK_EXPIRY | FEATURE_MASK_ERC20_CURRENCY;
    }

    function hasFeature(
        address tokenContract,
        uint256 tokenId,
        uint32 feature,
        uint256 offerId
    ) public view returns (bool) {
        StoredOffer storage offer = offers[tokenContract][tokenId][offerId];
        return _hasFeature(offer.features, feature);
    }

    function getFullOffer(
        address tokenContract,
        uint256 tokenId,
        uint256 offerId
    ) public view returns (FullOffer memory) {
        return _getFullOffer(offers[tokenContract][tokenId][offerId]);
    }

    function updatePrice(
        address tokenContract,
        uint256 tokenId,
        address currency,
        uint256 amount,
        uint256 offerId
    ) public {
        StoredOffer storage offer = offers[tokenContract][tokenId][offerId];
        _setETHorERC20Currency(offer, currency);
        offer.amount = amount;
    }
}

contract StorageTestBaseMinimal is OffersDataStorage {
    uint256 offerCounter;

    function newOffer(address tokenContract, uint256 tokenId) public {
        StoredOffer storage offer = offers[tokenContract][tokenId][++offerCounter];
        offer.maker = address(0x111);
        offer.amount = 0.4 ether;
        offer.features = 0;
    }

    function getExpectedActiveFeatures() public pure returns (uint32) {
        return 0;
    }

    function hasFeature(
        address tokenContract,
        uint256 tokenId,
        uint32 feature,
        uint256 offerId
    ) public view returns (bool) {
        StoredOffer storage offer = offers[tokenContract][tokenId][offerId];
        return _hasFeature(offer.features, feature);
    }

    function getFullOffer(
        address tokenContract,
        uint256 tokenId,
        uint256 offerId
    ) public view returns (FullOffer memory) {
        return _getFullOffer(offers[tokenContract][tokenId][offerId]);
    }
}

contract OffersDataStorageTest is DSTest {
    VM internal vm;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_EXPIRY = 1 << 5;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 6;

    function test_OfferStorageMinimalInit() public {
        StorageTestBaseMinimal dataStorage = new StorageTestBaseMinimal();
        dataStorage.newOffer(address(0x112), 21);
        OffersDataStorage.FullOffer memory offer = dataStorage.getFullOffer(address(0x112), 21, 1);
        assertEq(offer.amount, 0.4 ether, "price wrong");
        assertEq(offer.maker, address(0x111), "seller wrong");
        assertEq(offer.expiry, 0, "incorrect expiry");
        assertEq(offer.currency, address(0), "incorrect currency");
        assertEq(offer.findersFeeBps, 0, "incorrect finders fee");
        assertEq(offer.listingFeeBps, 0, "incorrect listing fee");
        assertEq(offer.listingFeeRecipient, address(0), "incorrect listing fee");
    }

    function test_OfferStorageInit() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newOffer(address(0x121), 21);
        OffersDataStorage.FullOffer memory offer = dataStorage.getFullOffer(address(0x121), 21, 1);
        assertEq(offer.amount, 0.4 ether, "price wrong");
        assertEq(offer.maker, address(0x111), "seller wrong");
        assertEq(offer.expiry, block.timestamp + 1_000, "incorrect expiry");
        assertEq(offer.currency, address(0x113), "incorrect currency");
        assertEq(offer.findersFeeBps, 2, "incorrect finders fee");
        assertEq(offer.listingFeeBps, 1, "incorrect listing fee");
        assertEq(offer.listingFeeRecipient, address(0x115), "incorrect listing fee");
    }

    function test_OfferStorageUpdatePrice() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newOffer(address(0x121), 21);
        OffersDataStorage.FullOffer memory offer = dataStorage.getFullOffer(address(0x121), 21, 1);
        assertEq(offer.amount, 0.4 ether, "price wrong");
        assertEq(offer.currency, address(0x113), "incorrect currency");
        dataStorage.updatePrice(address(0x121), 21, address(0), 1 ether, 1);
        offer = dataStorage.getFullOffer(address(0x121), 21, 1);
        assertEq(offer.amount, 1 ether, "price wrong");
        assertEq(offer.currency, address(0), "incorrect currency");
        assertTrue(!dataStorage.hasFeature(address(0x121), 21, FEATURE_MASK_ERC20_CURRENCY, 1));
    }
}
