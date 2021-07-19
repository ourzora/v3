// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {IModule} from "../../../interfaces/IModule.sol";

contract ReserveAuctionV1 is IModule {
    uint256 internal constant VERSION = 1;
    bytes32 internal constant TEST_MODULE_STORAGE_POSITION =
        keccak256("ReserveAuction.V1");

    struct Auction {
        // ID for the ERC721 token
        uint256 tokenId;
        // Address for the ERC721 contract
        address tokenContract;
        // Whether or not the auction curator has approved the auction to start
        bool approved;
        // The current highest bid amount
        uint256 amount;
        // The length of time to run the auction for, after the first bid was made
        uint256 duration;
        // The minimum amount of time left in the auction after a new bid is created
        uint256 timeBuffer;
        // The minimum percentage difference between the last bid and the current bid
        uint8 minimumIncrementPercentage;
        // The time of the first bid
        uint256 firstBidTime;
        // The minimum price of the first bid
        uint256 reservePrice;
        // The sale percentage to send to the curator
        uint8 curatorFeePercentage;
        // The address that should receive the funds once the NFT is sold.
        address tokenOwner;
        // The address of the current highest bid
        address payable bidder;
        // The address of the auction's curator.
        // The curator can reject or approve an auction
        address payable curator;
        // The address of the ERC-20 currency to run the auction with.
        // If set to 0x0, the auction will be run in ETH
        address auctionCurrency;
    }

    struct ReserveAuctionStorage {
        bool initialized;
        address zoraV1Protocol;
        mapping(uint256 => Auction) auctions;
    }

    modifier auctionExists(uint256 auctionId) {
        require(_exists(auctionId), "Auction doesn't exist");
        _;
    }

    function version() external pure override returns (uint256) {
        return VERSION;
    }

    function initialize(address _zoraV1Protocol) external {
        // This call should *technically* be internal, but we want it to show as external in utility libraries
        // so we can easily encode the initialization calldata
        require(
            msg.sender == address(this),
            "ReserveAuctionV1::initialize can not be called by external address"
        );
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        s.zoraV1Protocol = _zoraV1Protocol;
        s.initialized = true;
    }

    function _reserveAuctionStorage()
        internal
        pure
        returns (ReserveAuctionStorage storage s)
    {
        bytes32 position = TEST_MODULE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function _exists(uint256 auctionId) internal view returns (bool) {
        ReserveAuctionStorage storage s = _reserveAuctionStorage();
        return s.auctions[auctionId].tokenOwner != address(0);
    }
}
