// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

// ============ Imports ============

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
import {IZoraV1Market, IZoraV1Media} from "../../../interfaces/common/IZoraV1.sol";
import {IWETH} from "../../../interfaces/common/IWETH.sol";
import {IERC2981} from "../../../interfaces/common/IERC2981.sol";
import {CollectionRoyaltyRegistryV1} from "../../CollectionRoyaltyRegistry/V1/CollectionRoyaltyRegistryV1.sol";

/// @title Offers V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This module allows buyers to make an offer on any ERC-721
contract OffersV1 is ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    bytes4 constant ERC2981_INTERFACE_ID = 0x2a55205a;

    ERC20TransferHelper erc20TransferHelper;
    ERC721TransferHelper erc721TransferHelper;
    CollectionRoyaltyRegistryV1 royaltyRegistry;
    IZoraV1Media zoraV1Media;
    IZoraV1Market zoraV1Market;
    IWETH weth;

    // ============ Mutable Storage ============

    /// @notice The NFT collection offers created by a given user
    /// @dev User address => collection offer ID
    mapping(address => uint256[]) public userToCollectionOffers;

    /// @notice The NFT offers created by a given user
    /// @dev User address => NFT offer ID
    mapping(address => uint256[]) public userToNFTOffers;

    /// @notice The offers for a given NFT collection
    /// @dev NFT address => offer IDs
    mapping(address => uint256[]) public collectionToOffers;

    /// @notice The offers for a given NFT
    /// @dev NFT address => NFT ID => offer IDs
    mapping(address => mapping(uint256 => uint256[])) public nftToOffers;

    /// @notice Whether a user has an active offer for a given collection
    /// @dev User address => NFT address => boolean
    mapping(address => mapping(address => bool)) public userHasActiveCollectionOffer;

    /// @notice Whether a user has an active offer for a given NFT
    /// @dev User address => NFT address => NFT ID => boolean
    mapping(address => mapping(address => mapping(uint256 => bool))) public userHasActiveNFTOffer;

    /// @notice A mapping of IDs to their respective collection offer
    mapping(uint256 => CollectionOffer) public collectionOffers;

    /// @notice A mapping of IDs to their respective NFT offer
    mapping(uint256 => NFTOffer) public nftOffers;

    Counters.Counter collectionOfferCounter;
    Counters.Counter nftOfferCounter;

    enum OfferStatus {
        Active,
        Canceled,
        Accepted
    }

    struct CollectionOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 offerPrice;
        OfferStatus status;
    }

    struct NFTOffer {
        address buyer;
        address offerCurrency;
        address tokenContract;
        uint256 tokenID;
        uint256 offerPrice;
        OfferStatus status;
    }

    // ============ Events ============

    event CollectionOfferCreated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferCanceled(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferUpdated(uint256 indexed id, CollectionOffer offer);
    event CollectionOfferAccepted(uint256 indexed id, uint256 indexed tokenID, CollectionOffer offer);

    event NFTOfferCreated(uint256 indexed id, NFTOffer offer);
    event NFTOfferCanceled(uint256 indexed id, NFTOffer offer);
    event NFTOfferUpdated(uint256 indexed id, NFTOffer offer);
    event NFTOfferAccepted(uint256 indexed id, NFTOffer offer);

    // ============ Constructor ============

    /// @param _erc20TransferHelper The ZORA ERC-20 Transfer Helper address
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _zoraV1ProtocolMedia The ZORA NFT Protocol Media Contract address
    /// @param _royaltyRegistry The ZORA Collection Royalty Registry address
    /// @param _wethAddress WETH token address
    constructor(
        address _erc20TransferHelper,
        address _erc721TransferHelper,
        address _royaltyRegistry,
        address _zoraV1ProtocolMedia,
        address _wethAddress
    ) {
        erc20TransferHelper = ERC20TransferHelper(_erc20TransferHelper);
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
        royaltyRegistry = CollectionRoyaltyRegistryV1(_royaltyRegistry);
        zoraV1Media = IZoraV1Media(_zoraV1ProtocolMedia);
        zoraV1Market = IZoraV1Market(zoraV1Media.marketContract());
        weth = IWETH(_wethAddress);
    }

    // ============ Create Offers ============

    /// @notice Places an offer on a NFT collection
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @return The ID of the created collection offer
    function createCollectionOffer(
        address _tokenContract,
        uint256 _offerPrice,
        address _offerCurrency
    ) external payable nonReentrant returns (uint256) {
        require(userHasActiveCollectionOffer[msg.sender][_tokenContract] == false, "createCollectionOffer must update or cancel existing offer");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        collectionOfferCounter.increment();
        uint256 offerId = collectionOfferCounter.current();

        collectionOffers[offerId] = CollectionOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            offerPrice: _offerPrice,
            status: OfferStatus.Active
        });

        userToCollectionOffers[msg.sender].push(offerId);
        collectionToOffers[_tokenContract].push(offerId);
        userHasActiveCollectionOffer[msg.sender][_tokenContract] = true;

        emit CollectionOfferCreated(offerId, collectionOffers[offerId]);

        return offerId;
    }

    /// @notice Places an offer on a NFT
    /// @param _tokenContract The address of the ERC-721 token contract to place the offer
    /// @param _tokenID The ID of the ERC-721 token to place the offer
    /// @param _offerPrice The price of the offer
    /// @param _offerCurrency The address of the ERC-20 token to place an offer in, or address(0) for ETH
    /// @return The ID of the created NFT offer
    function createNFTOffer(
        address _tokenContract,
        uint256 _tokenID,
        uint256 _offerPrice,
        address _offerCurrency
    ) external payable nonReentrant returns (uint256) {
        require(IERC721(_tokenContract).ownerOf(_tokenID) != msg.sender, "createNFTOffer cannot make offer on NFT you own");
        require(userHasActiveNFTOffer[msg.sender][_tokenContract][_tokenID] == false, "createNFTOffer must update or cancel existing offer");

        // Ensure offered payment is valid and take custody of payment
        _handleIncomingTransfer(_offerPrice, _offerCurrency);

        nftOfferCounter.increment();
        uint256 offerID = nftOfferCounter.current();

        nftOffers[offerID] = NFTOffer({
            buyer: msg.sender,
            offerCurrency: _offerCurrency,
            tokenContract: _tokenContract,
            tokenID: _tokenID,
            offerPrice: _offerPrice,
            status: OfferStatus.Active
        });

        userToNFTOffers[msg.sender].push(offerID);
        nftToOffers[_tokenContract][_tokenID].push(offerID);
        userHasActiveNFTOffer[msg.sender][_tokenContract][_tokenID] = true;

        emit NFTOfferCreated(offerID, nftOffers[offerID]);

        return offerID;
    }

    // ============ Update Offers ============

    /// @notice Updates the price of a collection offer
    /// @param _offerID The ID of the collection offer
    /// @param _newOffer The new offer price
    function updateCollectionPrice(uint256 _offerID, uint256 _newOffer) external payable nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerID];

        require(offer.buyer == msg.sender, "updateCollectionPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "updateCollectionPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit CollectionOfferUpdated(_offerID, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency);
            offer.offerPrice -= decreaseAmount;

            emit CollectionOfferUpdated(_offerID, offer);
        }
    }

    /// @notice Updates the price of a NFT offer
    /// @param _offerID The ID of the NFT offer
    /// @param _newOffer The new offer price
    function updateNFTPrice(uint256 _offerID, uint256 _newOffer) external payable nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.buyer == msg.sender, "updateNFTPrice must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "updateNFTPrice must be active offer");

        if (_newOffer > offer.offerPrice) {
            uint256 increaseAmount = _newOffer - offer.offerPrice;
            // Ensure increased offer payment is valid and take custody of payment
            _handleIncomingTransfer(increaseAmount, offer.offerCurrency);

            offer.offerPrice += increaseAmount;

            emit NFTOfferUpdated(_offerID, offer);
        } else if (_newOffer < offer.offerPrice) {
            uint256 decreaseAmount = offer.offerPrice - _newOffer;

            _handleOutgoingTransfer(offer.buyer, decreaseAmount, offer.offerCurrency);
            offer.offerPrice -= decreaseAmount;

            emit NFTOfferUpdated(_offerID, offer);
        }
    }

    // ============ Cancel Offers ============

    /// @notice Cancels a collection offer
    /// @param _offerID The ID of the collection offer
    function cancelCollectionOffer(uint256 _offerID) external nonReentrant {
        CollectionOffer storage offer = collectionOffers[_offerID];

        require(offer.buyer == msg.sender, "cancelCollectionOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelCollectionOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userHasActiveCollectionOffer[offer.buyer][offer.tokenContract] = false;

        emit CollectionOfferCanceled(_offerID, offer);
    }

    /// @notice Cancels a NFT offer
    /// @param _offerID The ID of the NFT offer
    function cancelNFTOffer(uint256 _offerID) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.buyer == msg.sender, "cancelNFTOffer must be buyer from original offer");
        require(offer.status == OfferStatus.Active, "cancelNFTOffer must be active offer");

        _handleOutgoingTransfer(offer.buyer, offer.offerPrice, offer.offerCurrency);

        offer.status = OfferStatus.Canceled;
        userHasActiveNFTOffer[offer.buyer][offer.tokenContract][offer.tokenID] = false;

        emit NFTOfferCanceled(_offerID, offer);
    }

    // ============ Accept Offers ============

    /// @notice Accepts a collection offer
    /// @param _offerID The ID of the collection offer
    /// @param _tokenID The ID of the NFT to transfer
    function acceptCollectionOffer(uint256 _offerID, uint256 _tokenID) external nonReentrant {
        CollectionOffer storage collectionOffer = collectionOffers[_offerID];

        require(collectionOffer.status == OfferStatus.Active, "acceptCollectionOffer must be active offer");
        require(msg.sender == IERC721(collectionOffer.tokenContract).ownerOf(_tokenID), "acceptCollectionOffer must own token associated with offer");

        // Convert to NFTOffer for royalty payouts
        NFTOffer memory offer = _convertAcceptedCollectionOffer(collectionOffer, _tokenID);

        uint256 remainingProfit = offer.offerPrice;

        if (offer.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(offer);
        } else if (IERC165(offer.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(offer);
        }

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(collectionOffer.tokenContract, msg.sender, collectionOffer.buyer, _tokenID);

        collectionOffer.status = OfferStatus.Accepted;
        userHasActiveCollectionOffer[offer.buyer][offer.tokenContract] = false;

        emit CollectionOfferAccepted(_offerID, _tokenID, collectionOffer);
    }

    /// @notice Accepts a NFT offer
    /// @param _offerID The ID of the NFT offer
    function acceptNFTOffer(uint256 _offerID) external nonReentrant {
        NFTOffer storage offer = nftOffers[_offerID];

        require(offer.status == OfferStatus.Active, "acceptNFTOffer must be active offer");
        require(msg.sender == IERC721(offer.tokenContract).ownerOf(offer.tokenID), "acceptNFTOffer must own token associated with offer");

        // Payout respective parties, ensuring royalties are honored
        uint256 remainingProfit = offer.offerPrice;

        if (offer.tokenContract == address(zoraV1Media)) {
            remainingProfit = _handleZoraPayout(offer);
        } else if (IERC165(offer.tokenContract).supportsInterface(ERC2981_INTERFACE_ID)) {
            remainingProfit = _handleEIP2981Payout(offer);
        } else {
            remainingProfit = _handleRoyaltyRegistryPayout(offer);
        }

        // Transfer sale proceeds to seller
        _handleOutgoingTransfer(msg.sender, remainingProfit, offer.offerCurrency);

        // Transfer NFT to buyer
        erc721TransferHelper.transferFrom(offer.tokenContract, msg.sender, offer.buyer, offer.tokenID);

        offer.status = OfferStatus.Accepted;
        userHasActiveNFTOffer[offer.buyer][offer.tokenContract][offer.tokenID] = false;

        emit NFTOfferAccepted(_offerID, offer);
    }

    // ============ Private ============

    /// @notice Handle an incoming funds transfer, ensuring the sent amount is valid and the sender is solvent
    /// @param _amount The amount to be received
    /// @param _currency The currency to receive funds in, or address(0) for ETH
    function _handleIncomingTransfer(uint256 _amount, address _currency) private {
        if (_currency == address(0)) {
            require(msg.value >= _amount, "_handleIncomingTransfer msg value less than expected amount");
        } else {
            // We must check the balance that was actually transferred to this contract,
            // as some tokens impose a transfer fee and would not actually transfer the
            // full amount to the market, resulting in potentally locked funds
            IERC20 token = IERC20(_currency);
            uint256 beforeBalance = token.balanceOf(address(this));
            erc20TransferHelper.safeTransferFrom(_currency, msg.sender, address(this), _amount);
            uint256 afterBalance = token.balanceOf(address(this));
            require((beforeBalance + _amount) == afterBalance, "_handleIncomingTransfer token transfer call did not transfer expected amount");
        }
    }

    /// @notice Handle an outgoing funds transfer
    /// @dev Wraps ETH in WETH if the receiver cannot receive ETH, noop if the funds to be sent are 0 or recipient is invalid
    /// @param _dest The destination for the funds
    /// @param _amount The amount to be sent
    /// @param _currency The currency to send funds in, or address(0) for ETH
    function _handleOutgoingTransfer(
        address _dest,
        uint256 _amount,
        address _currency
    ) private {
        if (_amount == 0 || _dest == address(0)) {
            return;
        }
        // Handle ETH payment
        if (_currency == address(0)) {
            require(address(this).balance >= _amount, "_handleOutgoingTransfer insolvent");
            // Here increase the gas limit a reasonable amount above the default, and try
            // to send ETH to the recipient.
            (bool success, ) = _dest.call{value: _amount, gas: 30000}(new bytes(0));

            // If the ETH transfer fails (sigh), wrap the ETH and try send it as WETH.
            if (!success) {
                weth.deposit{value: _amount}();
                IERC20(address(weth)).safeTransfer(_dest, _amount);
            }
        } else {
            IERC20(_currency).safeTransfer(_dest, _amount);
        }
    }

    /// @notice Pays out royalties for ZORA NFTs
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleZoraPayout(NFTOffer memory offer) private returns (uint256) {
        IZoraV1Market.BidShares memory bidShares = zoraV1Market.bidSharesForToken(offer.tokenID);

        uint256 creatorProfit = zoraV1Market.splitShare(bidShares.creator, offer.offerPrice);
        uint256 prevOwnerProfit = zoraV1Market.splitShare(bidShares.prevOwner, offer.offerPrice);
        uint256 remainingProfit = offer.offerPrice - creatorProfit - prevOwnerProfit;

        // Pay out creator
        _handleOutgoingTransfer(zoraV1Media.tokenCreators(offer.tokenID), creatorProfit, offer.offerCurrency);
        // Pay out prev owner
        _handleOutgoingTransfer(zoraV1Media.previousTokenOwners(offer.tokenID), prevOwnerProfit, offer.offerCurrency);

        return remainingProfit;
    }

    /// @notice Pays out royalties for EIP-2981 compliant NFTs
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleEIP2981Payout(NFTOffer memory offer) private returns (uint256) {
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(offer.tokenContract).royaltyInfo(offer.tokenID, offer.offerPrice);

        uint256 remainingProfit = offer.offerPrice - royaltyAmount;

        _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, offer.offerCurrency);

        return remainingProfit;
    }

    /// @notice Pays out royalties for collections
    /// @param offer The offer to use as a reference for the royalty calculations
    /// @return The remaining profit from the sale
    function _handleRoyaltyRegistryPayout(NFTOffer memory offer) private returns (uint256) {
        (address royaltyReceiver, uint8 royaltyPercentage) = royaltyRegistry.collectionRoyalty(offer.tokenContract);

        uint256 remainingProfit = offer.offerPrice;
        uint256 royaltyAmount = (remainingProfit * royaltyPercentage) / 100;
        _handleOutgoingTransfer(royaltyReceiver, royaltyAmount, offer.offerCurrency);

        remainingProfit -= royaltyAmount;

        return remainingProfit;
    }

    /// @notice Converts an accepted collection offer to a NFT offer to use as a reference for the royalty calculations
    /// @param _collectionOffer The accepted collection offer
    /// @param _tokenID The NFT ID to complete the conversion
    /// @return The offer to use as a reference for the royalty calculations
    function _convertAcceptedCollectionOffer(CollectionOffer memory _collectionOffer, uint256 _tokenID) private view returns (NFTOffer memory) {
        return
            NFTOffer({
                buyer: msg.sender,
                offerCurrency: _collectionOffer.offerCurrency,
                tokenContract: _collectionOffer.tokenContract,
                tokenID: _tokenID,
                offerPrice: _collectionOffer.offerPrice,
                status: OfferStatus.Accepted
            });
    }
}
