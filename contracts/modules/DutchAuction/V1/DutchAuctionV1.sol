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

/// @title Dutch Auction V1
/// @author neokry <n@artiva.app>
/// @notice This contract allows users to list ERC-721 tokens with timed dutch auctions
contract DutchAuctionV1 is ReentrancyGuard, UniversalExchangeEventV1, IncomingTransferSupportV1, FeePayoutSupportV1, ModuleNamingSupportV1 {
    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice A mapping of NFTs to their respective auction ID
    /// @dev ERC-721 token address => ERC-721 token ID => auction ID
    mapping(address => mapping(uint256 => Auction)) public auctionForNFT;

    /// @notice The metadata of an auction
    /// @param seller The address that should receive the funds once the NFT is sold.
    /// @param auctionCurrency The address of the ERC-20 currency (0x0 for ETH) to run the auction with.
    /// @param sellerFundsRecipient The address of the recipient of the auction's bid
    /// @param finder The address of the current bid's finder
    /// @param findersFeeBps The sale bps to send to the winning bid finder
    /// @param startPrice The starting price amount
    /// @param endPrice The ending price amount
    /// @param startTime The time of the auction start
    /// @param duration The auction duration
    struct Auction {
        address seller;
        address auctionCurrency;
        address sellerFundsRecipient;
        address finder;
        uint16 findersFeeBps;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 duration;
    }

    /// @notice Emitted when an auction is created
    /// @param tokenContract The ERC-721 token address of the created auction
    /// @param tokenId The ERC-721 token ID of the created auction
    /// @param auction The metadata of the created auction
    event AuctionCreated(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

    /// @notice Emitted when the price of an auction is updated
    /// @param tokenContract The ERC-721 token address of the updated auction
    /// @param tokenId The ERC-721 token ID of the updated auction
    /// @param startPrice The updated start price of the auction
    /// @param endPrice The updated end price of the auction
    /// @param auction The metadata of the updated auction
    event AuctionPriceUpdated(address indexed tokenContract, uint256 indexed tokenId, uint256 startPrice, uint256 endPrice, Auction auction);

    /// @notice Emitted when an auction has ended
    /// @param tokenContract The ERC-721 token address of the auction
    /// @param tokenId The ERC-721 token ID of the auction
    /// @param winner The address of the winner bidder
    /// @param finder The address of the winning bid referrer
    /// @param auction The metadata of the ended auction
    event AuctionEnded(address indexed tokenContract, uint256 indexed tokenId, address indexed winner, address finder, Auction auction);

    /// @notice Emitted when an auction is canceled
    /// @param tokenContract The ERC-721 token address of the canceled auction
    /// @param tokenId The ERC-721 token ID of the canceled auction
    /// @param auction The metadata of the canceled auction
    event AuctionCanceled(address indexed tokenContract, uint256 indexed tokenId, Auction auction);

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
        ModuleNamingSupportV1("Dutch Auction: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    /// @notice Creates an auction for a given NFT
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token being auctioned for sale
    /// @param _startPrice The amount of time the auction should run for after the initial bid is placed
    /// @param _endPrice The minimum bid amount to start the auction
    /// @param _sellerFundsRecipient The address to send funds to once the token is sold
    /// @param _findersFeeBps The percentage of the sale amount to be sent to the referrer of the sale
    /// @param _auctionCurrency The address of the ERC-20 token to accept bids in, or address(0) for ETH
    /// @param _startTime The time to start the auction
    function createAuction(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _endPrice,
        address _sellerFundsRecipient,
        uint16 _findersFeeBps,
        address _auctionCurrency,
        uint256 _startTime,
        uint256 _duration
    ) external nonReentrant {
        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "createAuction must be token owner or operator"
        );
        require(erc721TransferHelper.isModuleApproved(msg.sender), "createAuction must approve DutchAuctionV1 module");
        require(
            IERC721(_tokenContract).isApprovedForAll(tokenOwner, address(erc721TransferHelper)),
            "createAuction must approve ERC721TransferHelper as operator"
        );
        require(_findersFeeBps <= 10000, "createAuction _findersFeeBps must be less than or equal to 10000");
        require(_sellerFundsRecipient != address(0), "createAuction must specify _sellerFundsRecipient");
        require(_startTime == 0 || _startTime > block.timestamp, "createAuction _startTime must be 0 or future block");
        require(_startPrice > _endPrice, "createAuction _startPrice must be greater than _endPrice");

        if (_startTime == 0) {
            _startTime = block.timestamp;
        }
        if (_duration == 0) {
            _duration = 1 days;
        }

        if (auctionForNFT[_tokenContract][_tokenId].seller != address(0)) {
            _cancelAuction(_tokenContract, _tokenId);
        }

        auctionForNFT[_tokenContract][_tokenId] = Auction({
            seller: tokenOwner,
            auctionCurrency: _auctionCurrency,
            sellerFundsRecipient: _sellerFundsRecipient,
            finder: address(0),
            findersFeeBps: _findersFeeBps,
            startPrice: _startPrice,
            endPrice: _endPrice,
            startTime: _startTime,
            duration: _duration
        });

        emit AuctionCreated(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);
    }

    /// @notice Update the price for a given auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _startPrice The new start price for the auction
    /// @param _endPrice The new end price for the auction
    function setAuctionPrices(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _startPrice,
        uint256 _endPrice
    ) external {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(msg.sender == auction.seller, "setAuctionPrices must be seller");
        require(_startPrice > _endPrice, "setAuctionPrices _startPrice must be greater than _endPrice");
        require(auction.startTime > block.timestamp, "setAuctionPrices auction startTime must be future block");

        auction.startPrice = _startPrice;
        auction.endPrice = _endPrice;

        emit AuctionPriceUpdated(_tokenContract, _tokenId, _startPrice, _endPrice, auction);
    }

    /// @notice Places a bid, transferring the ETH/ERC-20 to the seller and NFT to the buyer
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    /// @param _amount The bid amount to be transferred
    /// @param _finder The address of the referrer for this bid
    function createBid(
        address _tokenContract,
        uint256 _tokenId,
        uint256 _amount,
        address _finder
    ) external payable nonReentrant {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];
        require(auction.seller != address(0), "createBid auction doesn't exist");
        require(block.timestamp >= auction.startTime, "createBid auction hasn't started");
        require(block.timestamp <= auction.startTime + auction.duration, "createBid auction expired");

        uint256 price = getPrice(_tokenContract, _tokenId);
        require(_amount >= price, "createBid must send more than current price");

        // Ensure ETH/ERC-20 payment from buyer is valid and take custody
        _handleIncomingTransfer(price, auction.auctionCurrency);

        // Payout respective parties, ensuring royalties are honored
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(_tokenContract, _tokenId, _amount, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        // Payout optional protocol fee
        remainingProfit = _handleProtocolFeePayout(remainingProfit, auction.auctionCurrency);

        // Payout optional finder fee
        if (_finder != address(0)) {
            uint256 findersFee = (remainingProfit * auction.findersFeeBps) / 10000;
            _handleOutgoingTransfer(_finder, findersFee, auction.auctionCurrency, USE_ALL_GAS_FLAG);

            remainingProfit = remainingProfit - findersFee;
        }

        // Transfer remaining ETH/ERC-20 to seller
        _handleOutgoingTransfer(auction.sellerFundsRecipient, remainingProfit, auction.auctionCurrency, USE_ALL_GAS_FLAG);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(_tokenContract, auction.seller, msg.sender, _tokenId);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: auction.auctionCurrency, tokenId: 0, amount: _amount});

        emit ExchangeExecuted(auction.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit AuctionEnded(_tokenContract, _tokenId, msg.sender, _finder, auction);

        delete auctionForNFT[_tokenContract][_tokenId];
    }

    /// @notice Cancels an auction
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function cancelAuction(address _tokenContract, uint256 _tokenId) external {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];

        require(auction.seller != address(0), "cancelAuction auction doesn't exist");
        require(
            auction.startTime >= block.timestamp || auction.startTime + auction.duration <= block.timestamp,
            "cancelAuction auction currently in progress"
        );

        address tokenOwner = IERC721(_tokenContract).ownerOf(_tokenId);
        require(
            msg.sender == tokenOwner || IERC721(_tokenContract).isApprovedForAll(tokenOwner, msg.sender),
            "cancelAuction must be token owner or operator"
        );

        _cancelAuction(_tokenContract, _tokenId);
    }

    /// @dev Deletes canceled and invalid auctions
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function _cancelAuction(address _tokenContract, uint256 _tokenId) private {
        emit AuctionCanceled(_tokenContract, _tokenId, auctionForNFT[_tokenContract][_tokenId]);

        delete auctionForNFT[_tokenContract][_tokenId];
    }

    /// @dev Calculates current auction price
    /// @param _tokenContract The address of the ERC-721 token
    /// @param _tokenId The ID of the ERC-721 token
    function getPrice(address _tokenContract, uint256 _tokenId) public view returns (uint256) {
        Auction storage auction = auctionForNFT[_tokenContract][_tokenId];
        uint256 tickPerBlock = (auction.startPrice - auction.endPrice) / auction.duration;
        return
            block.timestamp >= auction.startTime + auction.duration
                ? auction.endPrice
                : auction.startPrice - ((block.timestamp - auction.startTime) * tickPerBlock);
    }
}
