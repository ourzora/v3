// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IModule} from "../../../interfaces/IModule.sol";
import {LibReserveAuctionV1} from "./LibReserveAuctionV1.sol";

contract ReserveAuctionV1 is IModule, ReentrancyGuard {
    using LibReserveAuctionV1 for LibReserveAuctionV1.ReserveAuctionStorage;

    bytes32 internal constant STORAGE_POSITION = keccak256("ReserveAuction.V1");

    function storageSlot() external pure override returns (bytes32) {
        return STORAGE_POSITION;
    }

    function auctions(uint256, uint256 _auctionId) external view returns (LibReserveAuctionV1.Auction memory) {
        return _reserveAuctionStorage().auctions[_auctionId];
    }

    function initialize(address _zoraV1ProtocolMedia, address _wethAddress) external {
        // TODO: verify the security of keeping this call external. It must be external so it can be added to
        // the function table and thus callable via delegatecall. However, there may be a better practice
        _reserveAuctionStorage().init(_zoraV1ProtocolMedia, _wethAddress);
    }

    function createAuction(
        uint256, /*_version*/
        uint256 _tokenId,
        address _tokenContract,
        uint256 _duration,
        uint256 _reservePrice,
        address payable _curator,
        address payable _fundsRecipient,
        uint8 _curatorFeePercentage,
        address _auctionCurrency
    ) public nonReentrant returns (uint256) {
        return
            _reserveAuctionStorage().createAuction(
                _tokenId,
                _tokenContract,
                _duration,
                _reservePrice,
                _curator,
                _fundsRecipient,
                _curatorFeePercentage,
                _auctionCurrency
            );
    }

    function setAuctionApproval(
        uint256, /*_version*/
        uint256 _auctionId,
        bool _approved
    ) external {
        _reserveAuctionStorage().setAuctionApproval(_auctionId, _approved);
    }

    function setAuctionReservePrice(
        uint256, /*_version*/
        uint256 _auctionId,
        uint256 _reservePrice
    ) external {
        _reserveAuctionStorage().setAuctionReservePrice(_auctionId, _reservePrice);
    }

    function createBid(
        uint256, /*_version*/
        uint256 _auctionId,
        uint256 _amount
    ) external payable nonReentrant {
        _reserveAuctionStorage().createBid(_auctionId, _amount);
    }

    function endAuction(
        uint256, /*_version*/
        uint256 _auctionId
    ) external nonReentrant {
        _reserveAuctionStorage().endAuction(_auctionId);
    }

    function cancelAuction(
        uint256, /*_version*/
        uint256 _auctionId
    ) external nonReentrant {
        _reserveAuctionStorage().cancelAuction(_auctionId);
    }

    function _reserveAuctionStorage() internal pure returns (LibReserveAuctionV1.ReserveAuctionStorage storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}
