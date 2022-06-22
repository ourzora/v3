// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {AsksDataStorage} from "../../../../modules/Asks/Omnibus/AsksDataStorage.sol";
import {VM} from "../../../utils/VM.sol";

contract StorageTestBaseFull is AsksDataStorage {
    function newAsk(address tokenContract, uint256 tokenId) public {
        StoredAsk storage ask = askForNFT[tokenContract][tokenId];
        ask.seller = address(0x111);
        ask.price = 0.4 ether;
        _setERC20Currency(ask, address(0x113));
        _setTokenGate(ask, address(0x114), 0.1 ether);
        _setListingFee(ask, 1, address(0x115));
        _setFindersFee(ask, 2);
        _setExpiryAndFundsRecipient(ask, uint96(block.timestamp + 1_000), address(0x112));
        _setBuyer(ask, address(0x116));
    }

    function getExpectedActiveFeatures() public pure returns (uint32) {
        return
            FEATURE_MASK_LISTING_FEE |
            FEATURE_MASK_FINDERS_FEE |
            FEATURE_MASK_ERC20_CURRENCY |
            FEATURE_MASK_TOKEN_GATE |
            FEATURE_MASK_RECIPIENT_OR_EXPIRY |
            FEATURE_MASK_BUYER;
    }

    function hasFeature(
        address tokenContract,
        uint256 tokenId,
        uint32 feature
    ) public view returns (bool) {
        StoredAsk storage ask = askForNFT[tokenContract][tokenId];
        return _hasFeature(ask.features, feature);
    }

    function getFullAsk(address tokenContract, uint256 tokenId) public view returns (FullAsk memory) {
        return _getFullAsk(askForNFT[tokenContract][tokenId]);
    }

    function updatePrice(
        address tokenContract,
        uint256 tokenId,
        address currency,
        uint256 price
    ) public {
        StoredAsk storage ask = askForNFT[tokenContract][tokenId];
        _setETHorERC20Currency(ask, currency);
        ask.price = price;
    }
}

contract StorageTestBaseMinimal is AsksDataStorage {
    function newAsk(address tokenContract, uint256 tokenId) public {
        StoredAsk storage ask = askForNFT[tokenContract][tokenId];
        ask.seller = address(0x111);
        ask.price = 0.4 ether;
        ask.features = 0;
    }

    function getExpectedActiveFeatures() public pure returns (uint32) {
        return 0;
    }

    function hasFeature(
        address tokenContract,
        uint256 tokenId,
        uint32 feature
    ) public view returns (bool) {
        StoredAsk storage ask = askForNFT[tokenContract][tokenId];
        return _hasFeature(ask.features, feature);
    }

    function getFullAsk(address tokenContract, uint256 tokenId) public view returns (FullAsk memory) {
        return _getFullAsk(askForNFT[tokenContract][tokenId]);
    }
}

/// @title
/// @notice
contract AsksDataStorageTest is DSTest {
    VM internal vm;

    uint32 constant FEATURE_MASK_LISTING_FEE = 1 << 3;
    uint32 constant FEATURE_MASK_FINDERS_FEE = 1 << 4;
    uint32 constant FEATURE_MASK_ERC20_CURRENCY = 1 << 5;
    uint32 constant FEATURE_MASK_TOKEN_GATE = 1 << 6;
    uint32 constant FEATURE_MASK_RECIPIENT_OR_EXPIRY = 1 << 7;
    uint32 constant FEATURE_MASK_BUYER = 1 << 8;

    function test_AskStorageMinimalInit() public {
        StorageTestBaseMinimal dataStorage = new StorageTestBaseMinimal();
        dataStorage.newAsk(address(0x112), 21);
        AsksDataStorage.FullAsk memory ask = dataStorage.getFullAsk(address(0x112), 21);
        assertEq(ask.seller, address(0x111), "seller wrong");
        assertEq(ask.price, 0.4 ether, "price wrong");
        assertEq(ask.sellerFundsRecipient, address(0), "seller funds recipient wrong");
        assertEq(ask.currency, address(0), "incorrect currency");
        assertEq(ask.buyer, address(0), "incorrect buyer");
        assertEq(ask.expiry, 0, "incorrect expiry");
        assertEq(ask.findersFeeBps, 0, "incorrect finders fee");
        assertEq(ask.tokenGate.token, address(0), "incorrect token gate");
        assertEq(ask.tokenGate.minAmount, 0, "incorrect token gate");
        assertEq(ask.listingFee.listingFeeBps, 0, "incorrect listing fee");
        assertEq(ask.listingFee.listingFeeRecipient, address(0), "incorrect listing fee");
    }

    function test_AskStorageInit() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newAsk(address(0x121), 21);
        AsksDataStorage.FullAsk memory ask = dataStorage.getFullAsk(address(0x121), 21);
        assertEq(ask.seller, address(0x111), "seller wrong");
        assertEq(ask.price, 0.4 ether, "price wrong");
        assertEq(ask.sellerFundsRecipient, address(0x112), "seller funds recipient wrong");
        assertEq(ask.currency, address(0x113), "incorrect currency");
        assertEq(ask.buyer, address(0x116), "incorrect buyer");
        assertEq(ask.expiry, block.timestamp + 1_000, "incorrect expiry");
        assertEq(ask.findersFeeBps, 2, "incorrect finders fee");
        assertEq(ask.tokenGate.token, address(0x114), "incorrect token gate");
        assertEq(ask.tokenGate.minAmount, 0.1 ether, "incorrect token gate");
        assertEq(ask.listingFee.listingFeeBps, 1, "incorrect listing fee");
        assertEq(ask.listingFee.listingFeeRecipient, address(0x115), "incorrect listing fee");
    }

    function test_AskStorageUpdatePrice() public {
        StorageTestBaseFull dataStorage = new StorageTestBaseFull();
        dataStorage.newAsk(address(0x121), 21);
        AsksDataStorage.FullAsk memory ask = dataStorage.getFullAsk(address(0x121), 21);
        assertEq(ask.price, 0.4 ether, "price wrong");
        assertEq(ask.currency, address(0x113), "incorrect currency");
        dataStorage.updatePrice(address(0x121), 21, address(0), 1 ether);
        ask = dataStorage.getFullAsk(address(0x121), 21);
        assertEq(ask.price, 1 ether, "price wrong");
        assertEq(ask.currency, address(0), "incorrect currency");
        assertTrue(!dataStorage.hasFeature(address(0x121), 21, FEATURE_MASK_ERC20_CURRENCY));
    }
}
