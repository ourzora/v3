// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {OutgoingTransferSupportV1} from "../../../common/OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";
import {IncomingTransferSupportV1} from "../../../common/IncomingTransferSupport/V1/IncomingTransferSupportV1.sol";
import {FeePayoutSupportV1} from "../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Reserve Auction V1
/// @author tbtstl <t@zora.co>
/// @notice This contract allows users to list and bid on ERC-721 tokens with timed reserve auctions
contract ReserveAuctionV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;
    /// @notice The minimum amount of time left in an auction after a new bid is created
    uint256 constant TIME_BUFFER = 15 minutes;
    /// @notice The minimum percentage difference between the last bid amount and the current bid.
    uint8 constant MIN_BID_INCREMENT_PERCENTAGE = 10;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The auction for a given NFT, if one exists
    /// @dev ERC-721 token contract => ERC-721 token ID => Auction
    mapping(address => mapping(uint256 => Auction)) public auctionForNFT;

    /// @notice The metadata of an auction
    /// @param seller The address of the seller creating the auction
    /// @param currency The address of the ERC-20, or address(0) for ETH, required to bid
    /// @param sellerFundsRecipient The address to send funds after the auction is settled
    /// @param bidder The address of the highest bidder
    /// @param finder The address of the referrer of the highest bid
    /// @param findersFeeBps The fee to the referrer of the winning bid
    /// @param amount The highest bid on the auction
    /// @param duration The duration time of the auction after the first bid
    /// @param startTime The start time of the auction
    /// @param firstBidTime The time of the first bid
    /// @param reservePrice The price to create the first bid
    struct Auction {
        address seller;
        address currency;
        address sellerFundsRecipient;
        address bidder;
        address finder;
        uint16 findersFeeBps;
        uint256 amount;
        uint256 duration;
        uint256 startTime;
        uint256 firstBidTime;
        uint256 reservePrice;
    }

    /// @notice Emitted when an auction is created
    /// @param tokenContract The ERC-721 token address of the created auction
    /// @param tokenId The ERC-721 token ID of the created auction
    /// @param auction The metadata of the created auction
    event AuctionCreated(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when the reserve price of an auction is updated
    /// @param tokenContract The ERC-721 token address of the updated auction
    /// @param tokenId The ERC-721 token ID of the updated auction
    /// @param reservePrice The reserve price of the updated auction
    /// @param auction The metadata of the updated auction
    event AuctionReservePriceUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed reservePrice, Auction auction);

    /// @notice Emitted when an auction is canceled
    /// @param tokenContract The ERC-721 token address of the canceled auction
    /// @param tokenId The ERC-721 token ID of the canceled auction
    /// @param auction The metadata of the canceled auction
    event AuctionCanceled(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when a bid is placed on an auction
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token ID of the auction
    /// @param amount The bid on the auction
    /// @param bidder The address of the bidder
    /// @param firstBid Whether the bid started the auction
    /// @param extended Whether the bid extended the auction
    /// @param duration The duration of the auction
    event AuctionBid(
        address indexed tokenContract,
        uint256 indexed tokenId,
        uint256 indexed amount,
        address bidder,
        bool firstBid,
        bool extended,
        uint256 duration
    );

    /// @notice Emitted when an auction has ended
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token ID of the auction
    /// @param winner The address of the winner bidder
    /// @param finder The referrer of the winning bid
    /// @param auction The metadata of the settled auction
    event AuctionEnded(address indexed tokenContract, uint256 indexed tokenId, address indexed winner, address finder, Auction auction);

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZoraProtocolFeeSettingsV1 address
    /// @param _wethAddress The WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _wethAddress
    )
        IncomingTransferSupportV1(_erc20TransferHelper)
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _wethAddress, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Reserve Auction: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,----------------.
    //     / \            |ReserveAuctionV1|
    //   Caller           `-------+--------'
    //     |    createAuction()   |
    //     | --------------------->
    //     |                      |
    //     |                      |
    //     |    _____________________________________________________________________
    //     |    ! ALT  /  Inactive auction exists for this token?                    !
    //     |    !_____/           |                                                  !
    //     |    !                 |----.                                             !
    //     |    !                 |    | _cancelAuction(_tokenContract, _tokenId)    !
    //     |    !                 |<---'                                             !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                      |
    //     |                      |
    //     |    ______________________________________________________
    //     |    ! ALT  /  Start time set to 0?                        !
    //     |    !_____/           |                                   !
    //     |    !                 |----.                              !
    //     |    !                 |    | mark as immediate auction    !
    //     |    !                 |<---'                              !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[mark as future auction]~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                      |
    //     |                      |----.
    //     |                      |    | create auction
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | emit AuctionCreated()
    //     |                      |<---'
    //   Caller           ,-------+--------.
    //     ,-.            |ReserveAuctionV1|
    //     `-'            `----------------'
    //     /|\
    //      |
    //     / \
    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token being auctioned for sale
    /// @param _duration The amount of time the auction should run for after the initial bid is placed
    /// @param _reservePrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _findersFeeBps The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @param _startTime The time to start the auction
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _reservePrice,
        address _sellerFundsRecipient,
        uint16 _findersFeeBps,
        address _auctionCurrency,
        uint256 _startTime
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);

        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAuction must be token owner or operator"
        );
        require(erc721TransferHelper.isModuleApproved(msg.sender), "createAuction must approve ReserveAuctionV1 module");
        require(
            IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createAuction must approve ERC721TransferHelper as operator"
        );
        require(_findersFeeBps <= 10000, "createAuction _findersFeeBps must be less than or equal to 10000");
        require(_sellerFundsRecipient != address(0), "createAuction must specify _sellerFundsRecipient");
        require(_startTime == 0 || _startTime > block.timestamp, "createAuction _startTime must be 0 or future timestamp");

        if (auctionForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelAuction(_tokenContract, _tokenId);
        }

        if (_startTime == 0) {
            _startTime = block.timestamp;
        }

        auctionForNFT[_tokenContract][_tokenId] = Auction({
            seller: tokenOwner,
            currency: _auctionCurrency,
            sellerFundsRecipient: _sellerFundsRecipient,
            bidder: address(0),
            finder: address(0),
            findersFeeBps: _findersFeeBps,
            amount: 0,
            duration: _duration,
            startTime: _startTime,
            firstBidTime: 0,
            reservePrice: _reservePrice
        });

        emit AuctionCreated(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |                ,----------------.
    //     / \               |ReserveAuctionV1|
    //   Caller              `-------+--------'
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
    //   Caller              ,-------+--------.
    //     ,-.               |ReserveAuctionV1|
    //     `-'               `----------------'
    //     /|\
    //      |
    //     / \
    /// @notice Updates the reserve price for a given auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _reservePrice The new reserve price for the auction
    function setAuctionReservePrice(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(msg.sender == auction.seller, "setAuctionReservePrice must be seller");
        require(auction.firstBidTime == 0, "setAuctionReservePrice auction has already started");

        auction.reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_tokenContract, _tokenId, _reservePrice, auction);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,----------------.
    //     / \            |ReserveAuctionV1|
    //   Caller           `-------+--------'
    //     |    cancelAuction()   |
    //     | --------------------->
    //     |                      |
    //     |                      |----.
    //     |                      |    | emit AuctionCanceled()
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | delete auction
    //     |                      |<---'
    //   Caller           ,-------+--------.
    //     ,-.            |ReserveAuctionV1|
    //     `-'            `----------------'
    //     /|\
    //      |
    //     / \
    /// @notice Cancels an auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external {
        Auction memory auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != address(0), "cancelAuction auction doesn't exist");
        require(auction.firstBidTime == 0, "cancelAuction auction already started");

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "cancelAuction must be token owner or operator"
        );

        _cancelAuction(_tokenContract, _tokenId);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,----------------.          ,--------------------.                  ,-------------------.
    //     / \            |ReserveAuctionV1|          |ERC721TransferHelper|                  |ERC20TransferHelper|
    //   Caller           `-------+--------'          `---------+----------'                  `---------+---------'
    //     |      createBid()     |                             |                                       |
    //     | --------------------->                             |                                       |
    //     |                      |                             |                                       |
    //     |                      |                             |                                       |
    //     |    ____________________________________________________________________________________________________________________________
    //     |    ! ALT  /  First bid?                            |                                       |                                   !
    //     |    !_____/           |                             |                                       |                                   !
    //     |    !                 |----.                        |                                       |                                   !
    //     |    !                 |    | start auction          |                                       |                                   !
    //     |    !                 |<---'                        |                                       |                                   !
    //     |    !                 |                             |                                       |                                   !
    //     |    !                 |        transferFrom()       |                                       |                                   !
    //     |    !                 | ---------------------------->                                       |                                   !
    //     |    !                 |                             |                                       |                                   !
    //     |    !                 |                             |----.                                                                      !
    //     |    !                 |                             |    | transfer NFT from seller to escrow                                   !
    //     |    !                 |                             |<---'                                                                      !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    ! [refund previous bidder]                      |                                       |                                   !
    //     |    !                 |                        handle outgoing refund                       |                                   !
    //     |    !                 | -------------------------------------------------------------------->                                   !
    //     |    !                 |                             |                                       |                                   !
    //     |    !                 |                             |                                       |----.                              !
    //     |    !                 |                             |                                       |    | transfer tokens to bidder    !
    //     |    !                 |                             |                                       |<---'                              !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                      |                             |                                       |
    //     |                      |                         handle incoming bid                         |
    //     |                      | -------------------------------------------------------------------->
    //     |                      |                             |                                       |
    //     |                      |                             |                                       |----.
    //     |                      |                             |                                       |    | transfer tokens to escrow
    //     |                      |                             |                                       |<---'
    //     |                      |                             |                                       |
    //     |                      |                             |                                       |
    //     |    ___________________________________________     |                                       |
    //     |    ! ALT  /  Bid placed within 15 min of end? !    |                                       |
    //     |    !_____/           |                        !    |                                       |
    //     |    !                 |----.                   !    |                                       |
    //     |    !                 |    | extend auction    !    |                                       |
    //     |    !                 |<---'                   !    |                                       |
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!    |                                       |
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!    |                                       |
    //     |                      |                             |                                       |
    //     |                      |----.                        |                                       |
    //     |                      |    | emit AuctionBid()      |                                       |
    //     |                      |<---'                        |                                       |
    //   Caller           ,-------+--------.          ,---------+----------.                  ,---------+---------.
    //     ,-.            |ReserveAuctionV1|          |ERC721TransferHelper|                  |ERC20TransferHelper|
    //     `-'            `----------------'          `--------------------'                  `-------------------'
    //     /|\
    //      |
    //     / \
    /// @notice Places a bid on the auction, holding the funds in escrow and refunding any previous bids
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _amount The amount to bid
    /// @param _finder The address of this bid's referrer
    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != address(0), "createBid auction doesn't exist");
        require(block.timestamp >= auction.startTime, "createBid auction hasn't started");
        require(_amount >= auction.reservePrice, "createBid must send at least reservePrice");
        unchecked {
            require(auction.firstBidTime == 0 || block.timestamp < (auction.firstBidTime + auction.duration), "createBid auction expired");
            require(
                _amount >= (auction.amount + ((auction.amount * MIN_BID_INCREMENT_PERCENTAGE) / 100)),
                "createBid must send more than 10% of last bid amount"
            );
        }

        bool firstBid;
        bool extended;

        // If first bid --
        if (auction.firstBidTime == 0) {
            // Store time of bid
            auction.firstBidTime = block.timestamp;
            // Mark as first bid
            firstBid = true;
            // Transfer NFT into escrow
            erc721TransferHelper.transferFrom(_tokenContract, auction.seller, address(this), _tokenId);

            // Else refund previous bidder
        } else {
            _handleOutgoingTransfer(auction.bidder, auction.amount, auction.currency, 30000);
        }

        // Ensure incoming bid payment is valid and take custody
        _handleIncomingTransfer(_amount, auction.currency);

        // Update storage
        auction.amount = _amount;
        auction.bidder = msg.sender;
        auction.finder = _finder;

        unchecked {
            // Get remaining time
            uint256 auctionTimeRemaining = auction.firstBidTime + auction.duration - block.timestamp;

            // If bid is placed within 15 minutes of the auction ending --
            if (auctionTimeRemaining < TIME_BUFFER) {
                // Extend auction so 15 minutes are left from time of bid
                auction.duration += (TIME_BUFFER - auctionTimeRemaining);
                // Mark as extended
                extended = true;
            }
        }

        emit AuctionBid(_tokenContract, _tokenId, _amount, msg.sender, firstBid, extended, auction.duration);
    }

    //     ,-.
    //     `-'
    //     /|\
    //      |             ,----------------.
    //     / \            |ReserveAuctionV1|
    //   Caller           `-------+--------'
    //     |    settleAuction()   |
    //     | --------------------->
    //     |                      |
    //     |                      |----.
    //     |                      |    | validate auction ended
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | handle royalty payouts
    //     |                      |<---'
    //     |                      |
    //     |                      |
    //     |    ______________________________________________________
    //     |    ! ALT  /  finders fee configured for this auction?    !
    //     |    !_____/           |                                   !
    //     |    !                 |----.                              !
    //     |    !                 |    | handle finders fee payout    !
    //     |    !                 |<---'                              !
    //     |    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |    !~[noop]~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
    //     |                      |
    //     |                      |----.
    //     |                      |    | handle seller funds recipient payout
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | transfer NFT from escrow to winning bidder
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | emit ExchangeExecuted()
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | emit AuctionEnded()
    //     |                      |<---'
    //     |                      |
    //     |                      |----.
    //     |                      |    | delete auction from contract
    //     |                      |<---'
    //   Caller           ,-------+--------.
    //     ,-.            |ReserveAuctionV1|
    //     `-'            `----------------'
    //     /|\
    //      |
    //     / \
    /// @notice Ends an auction, pays out respective parties and transfers the NFT to the winning bidder
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function settleAuction(address _tokenContract, uint256 _tokenId) external nonReentrant {
        Auction memory auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != address(0), "settleAuction auction doesn't exist");
        require(auction.firstBidTime != 0, "settleAuction auction hasn't begun");
        unchecked {
            require(block.timestamp >= (auction.firstBidTime + auction.duration), "settleAuction auction hasn't completed");
        }

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, auction.amount, auction.currency, 200000);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, auction.currency);

        // Payout optional finders fee
        if (auction.finder != address(0)) {
            uint256 finderFee = (remainingProfit * auction.findersFeeBps) / 10000;
            _handleOutgoingTransfer(auction.finder, finderFee, auction.currency, 30000);

            remainingProfit -= finderFee;
        }

        // Transfer remaining funds to seller
        _handleOutgoingTransfer(auction.sellerFundsRecipient, remainingProfit, auction.currency, 30000);

        // Transfer NFT to winning bidder
        IERC721(_tokenContract).transferFrom(address(this), auction.bidder, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: auction.currency, tokenId: 0, amount: auction.amount});

        emit ExchangeExecuted(auction.seller, auction.bidder, userAExchangeDetails, userBExchangeDetails);
        emit AuctionEnded(_tokenContract, _tokenId, auction.bidder, auction.finder, auction);

        delete auctionForNFT[_tokenContract][_tokenId];
    }

    /// @dev Deletes canceled and invalid auctions
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function _cancelAuction(address _tokenContract, uint256 _tokenId) private {
        emit AuctionCanceled(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);

        delete auctionForNFT[_tokenContract][_tokenId];
    }
}
