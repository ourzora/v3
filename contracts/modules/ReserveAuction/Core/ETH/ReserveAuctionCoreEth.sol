// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Reserve Auction Core ETH
/// @author kulkarohan
/// @notice Module for minimal ETH timed reserve auctions for ERC-721 tokens
contract ReserveAuctionCoreEth is ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint256 constant TIME_BUFFER = 15 minutes;

    /// @notice The minimum percentage difference between the last bid amount and the current bid
    uint8 constant MIN_BID_INCREMENT_PERCENTAGE = 10;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The auction for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token id => Auction
    mapping(address => mapping(uint256 => Auction)) public auctionForNFT;

    /// @notice The metadata for a given auction
    /// @param seller The address of the seller
    /// @param reservePrice The reserve price to start the auction
    /// @param sellerFundsRecipient The address funds are sent after the auction
    /// @param highestBid The highest bid on the auction
    /// @param highestBidder The address of the highest bidder
    /// @param duration The length of time after the first bid the auction is active
    /// @param startTime The first time a bid can be placed
    /// @param firstBidTime The time of the first bid
    struct Auction {
        address seller;
        uint96 reservePrice;
        address sellerFundsRecipient;
        uint96 highestBid;
        address highestBidder;
        uint32 duration;
        uint32 startTime;
        uint32 firstBidTime;
    }

    /// @notice Emitted when an auction is created
    /// @param tokenContract The ERC-721 token address of the created auction
    /// @param tokenId The ERC-721 token id of the created auction
    /// @param auction The metadata of the created auction
    event AuctionCreated(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when a reserve price is updated
    /// @param tokenContract The ERC-721 token address of the updated auction
    /// @param tokenId The ERC-721 token id of the updated auction
    /// @param auction The metadata of the updated auction
    event AuctionReservePriceUpdated(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when an auction is canceled
    /// @param tokenContract The ERC-721 token address of the canceled auction
    /// @param tokenId The ERC-721 token id of the canceled auction
    /// @param auction The metadata of the canceled auction
    event AuctionCanceled(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when a bid is placed
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token id of the auction
    /// @param firstBid If the bid started the auction
    /// @param extended If the bid extended the auction
    /// @param auction The metadata of the auction
    event AuctionBid(address indexed tokenContract, uint256 indexed tokenId, bool firstBid, bool extended, Auction auction);

    /// @notice Emitted when an auction has ended
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token id of the auction
    /// @param auction The metadata of the settled auction
    event AuctionEnded(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    constructor(
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Reserve Auction Core ETH")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,---------------------.
    //     / \            |ReserveAuctionCoreEth|
    //   Caller           `----------+----------'
    //     |     createAuction()     |
    //     | ----------------------->|
    //     |                         |
    //     |                         ----.
    //     |                             | store auction metadata
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | emit AuctionCreated()
    //     |                         <---'
    //   Caller           ,----------+----------.
    //     ,-.            |ReserveAuctionCoreEth|
    //     `-'            `---------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _duration The amount of time the auction should run after an initial bid
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _startTime The time the auction can begin accepting bids
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint256 _startTime
    ) external nonReentrant {
        // Get the owner of the specified token
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        // Ensure the caller is the owner or an approved operator
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAuction must be token owner or operator"
        );

        // Ensure that a funds recipient is specified
        require(_sellerFundsRecipient != address(0), "createAuction must specify _sellerFundsRecipient");

        // Store the auction metadata
        auctionForNFT[_tokenContract][_tokenId].seller = tokenOwner;
        auctionForNFT[_tokenContract][_tokenId].reservePrice = uint96(_reservePrice);
        auctionForNFT[_tokenContract][_tokenId].sellerFundsRecipient = _sellerFundsRecipient;
        auctionForNFT[_tokenContract][_tokenId].duration = uint32(_duration);
        auctionForNFT[_tokenContract][_tokenId].startTime = uint32(_startTime);

        emit AuctionCreated(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,---------------------.
    //     / \            |ReserveAuctionCoreEth|
    //   Caller           `----------+----------'
    //     | setAuctionReservePrice()|
    //     | ------------------------>
    //     |                         |
    //     |                         |----.
    //     |                         |    | update reserve price
    //     |                         |<---'
    //     |                         |
    //     |                         |----.
    //     |                         |    | emit AuctionReservePriceUpdated()
    //     |                         |<---'
    //   Caller           ,----------+----------.
    //     ,-.            |ReserveAuctionCoreEth|
    //     `-'            `---------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Updates the auction reserve price for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    /// @param _reservePrice The new reserve price
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external nonReentrant {
        // Get the auction for the specified token
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Ensure the auction has not started
        require(auction.firstBidTime == 0, "setAuctionReservePrice auction already started");

        // Ensure the caller is the seller
        require(msg.sender == auction.seller, "setAuctionReservePrice must be seller");

        // Update the reserve price
        auction.reservePrice = uint96(_reservePrice);

        emit AuctionReservePriceUpdated(_tokenContract, _tokenId, auction);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,---------------------.
    //     / \            |ReserveAuctionCoreEth|
    //   Caller           `----------+----------'
    //     |     cancelAuction()     |
    //     | ----------------------->|
    //     |                         |
    //     |                         ----.
    //     |                             | emit AuctionCanceled()
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | delete auction
    //     |                         <---'
    //   Caller           ,----------+----------.
    //     ,-.            |ReserveAuctionCoreEth|
    //     `-'            `---------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Cancels the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the auction for the specified token
        Auction memory auction = auctionForNFT[_tokenContract][_tokenId];

        // Ensure the auction has not started
        require(auction.firstBidTime == 0, "cancelAuction auction already started");

        // Ensure the caller is the seller or a new owner
        require(
            msg.sender == auction.seller || msg.sender == IERC721(_tokenContract).ownerOf(_tokenId),
            "cancelAuction must be seller or token owner"
        );

        emit AuctionCanceled(_tokenContract, _tokenId, auction);

        // Remove the auction from storage
        delete auctionForNFT[_tokenContract][_tokenId];
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,---------------------.          ,--------------------.
    //     / \            |ReserveAuctionCoreEth|          |ERC721TransferHelper|
    //   Caller           `----------+----------'          `---------+----------'
    //     |       createBid()       |                               |
    //     | ----------------------->|                               |
    //     |                         |                               |
    //     |                         |                               |
    //     |    __________________________________________________________________________________________________
    //     |    ! ALT  /  First bid? |                               |                                            !
    //     |    !_____/              |                               |                                            !
    //     |    !                    ----.                           |                                            !
    //     |    !                        | start auction             |                                            !
    //     |    !                    <---'                           |                                            !
    //     |    !                    |                               |                                            !
    //     |    !                    |        transferFrom()         |                                            !
    //     |    !                    |------------------------------>|                                            !
    //     |    !                    |                               |                                            !
    //     |    !                    |                               |----.                                       !
    //     |    !                    |                               |    | transfer NFT from seller to escrow    !
    //     |    !                    |                               |<---'                                       !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    ! [refund previous bidder]                           |                                            !
    //     |    !                    ----.                           |                                            !
    //     |    !                        | transfer ETH to bidder    |                                            !
    //     |    !                    <---'                           |                                            !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                         |                               |
    //     |                         |                               |
    //     |    _____________________________________________        |
    //     |    ! ALT  /  Bid placed within 15 min of end?   !       |
    //     |    !_____/              |                       !       |
    //     |    !                    ----.                   !       |
    //     |    !                        | extend auction    !       |
    //     |    !                    <---'                   !       |
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!       |
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!       |
    //     |                         |                               |
    //     |                         ----.                           |
    //     |                             | emit AuctionBid()         |
    //     |                         <---'                           |
    //   Caller           ,----------+----------.          ,---------+----------.
    //     ,-.            |ReserveAuctionCoreEth|          |ERC721TransferHelper|
    //     `-'            `---------------------'          `--------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Places a bid on the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function createBid(address _tokenContract, uint256 _tokenId) external payable nonReentrant {
        // Get the auction for the specified token
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        // Cache the seller
        address seller = auction.seller;

        // Ensure the auction exists
        require(seller != address(0), "createBid auction does not exist");

        // Ensure the auction has started or is valid to start
        require(block.timestamp >= auction.startTime, "createBid auction not started");

        // Cache more auction metadata
        uint256 highestBid = auction.highestBid;
        uint256 duration = auction.duration;
        uint256 firstBidTime = auction.firstBidTime;

        // Used to emit whether the bid started the auction
        bool firstBid;

        // If this is the first bid, start the auction
        if (firstBidTime == 0) {
            // Ensure the bid meets the reserve price
            require(msg.value >= auction.reservePrice, "createBid must meet reserve price");

            // Store the current time as the first bid time
            auction.firstBidTime = uint32(block.timestamp);

            // Mark the bid as the first
            firstBid = true;

            // Transfer the NFT from the seller into escrow for the rest of the auction
            // Reverts if the seller does not own the token or did not approve the ERC721TransferHelper
            erc721TransferHelper.transferFrom(_tokenContract, seller, address(this), _tokenId);

            // Else this is a subsequent bid, so refund the previous bidder
        } else {
            // Ensure the auction has not ended
            require(block.timestamp < (firstBidTime + duration), "createBid auction expired");

            // Ensure the bid is at least 10% higher than the previous bid
            require(msg.value >= (highestBid + ((highestBid * MIN_BID_INCREMENT_PERCENTAGE) / 100)), "createBid must meet minimum bid");

            // Refund the previous bidder
            _handleOutgoingTransfer(auction.highestBidder, highestBid, address(0), 50000);
        }

        // Store the attached ETH as the highest bid
        auction.highestBid = uint96(msg.value);

        // Store the caller as the highest bidder
        auction.highestBidder = msg.sender;

        // Used to emit whether the bid extended the auction
        bool extended;

        // Get the auction time remaining
        uint256 auctionTimeRemaining = firstBidTime + duration - block.timestamp;

        // If the bid is within 15 minutes of the end, extend the auction
        if (auctionTimeRemaining < TIME_BUFFER) {
            // Add (15 minutes - remaining time) to the duration so that 15 minutes are left
            auction.duration += uint32(TIME_BUFFER - auctionTimeRemaining);

            // Mark the bid as one that extended the auction
            extended = true;
        }

        emit AuctionBid(_tokenContract, _tokenId, firstBid, extended, auction);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,---------------------.
    //     / \            |ReserveAuctionCoreEth|
    //   Caller           `----------+----------'
    //     |     settleAuction()     |
    //     | ----------------------->|
    //     |                         |
    //     |                         ----.
    //     |                             | validate auction ended
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | handle royalty payouts
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | handle seller funds recipient payout
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | transfer NFT from escrow to winning bidder
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | emit AuctionEnded()
    //     |                         <---'
    //     |                         |
    //     |                         ----.
    //     |                             | delete auction from contract
    //     |                         <---'
    //   Caller           ,----------+----------.
    //     ,-.            |ReserveAuctionCoreEth|
    //     `-'            `---------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Ends the auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The id of the ERC-721 token
    function settleAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        // Get the auction for the specified token
        Auction memory auction = auctionForNFT[_tokenContract][_tokenId];

        // Cache the time of the first bid
        uint256 firstBidTime = auction.firstBidTime;

        // Ensure the auction had started
        require(firstBidTime != 0, "settleAuction auction not started");

        // Ensure the auction has ended
        require(block.timestamp >= (firstBidTime + auction.duration), "settleAuction auction not finished");

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, auction.highestBid, address(0), 300000);

        // Payout the module fee, if configured by the owner
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the funds recipient
        _handleOutgoingTransfer(auction.sellerFundsRecipient, remainingProfit, address(0), 50000);

        // Transfer the NFT to the winning bidder
        IERC721(_tokenContract).transferFrom(address(this), auction.highestBidder, _tokenId);

        emit AuctionEnded(_tokenContract, _tokenId, auction);

        // Remove the auction from storage
        delete auctionForNFT[_tokenContract][_tokenId];
    }
}
