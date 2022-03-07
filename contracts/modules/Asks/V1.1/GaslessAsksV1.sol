// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
import {UniversalExchangeEventV1} from "../../../common/UniversalExchangeEvent/V1/UniversalExchangeEventV1.sol";
import {OutgoingTransferSupportV1} from "../../../common/OutgoingTransferSupport/V1/OutgoingTransferSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";

/// @title Gasless Asks V1.0
/// @author tbtstl <t@zora.co>
/// @notice This module allows sellers to list an owned ERC-721 token for sale for a given price in a given currency, and allows buyers to purchase from those asks
contract GaslessAsksV1 is ReentrancyGuard, UniversalExchangeEventV1, OutgoingTransferSupportV1, ModuleNamingSupportV1 {
    /// @notice The EIP-712 type for a signed ask
    bytes32 private immutable SIGNED_ASK_TYPEHASH =
        keccak256("SignedAsk(address seller,address tokenContract,uint256 tokenId,uint256 askPrice,uint256 deadline)");

    /// @notice The EIP-712 domain separator
    bytes32 private immutable EIP_712_DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA")),
                keccak256(bytes("3")),
                _chainID(),
                address(this)
            )
        );

    /// @dev The indicator to pass all remaining gas when paying out royalties
    uint256 private constant USE_ALL_GAS_FLAG = 0;

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    event AskFilled(address indexed tokenContract, uint256 indexed tokenId, uint256 indexed askPrice, address indexed buyer, address seller);

    constructor(address _erc721TransferHelper, address _wethAddress)
        OutgoingTransferSupportV1(_wethAddress)
        ModuleNamingSupportV1("Gasless Asks: v1.0")
    {
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    function fillSignedAsk(
        address _seller,
        address _tokenContract,
        uint256 _tokenId,
        uint256 _askPrice,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public payable {
        require(_deadline == 0 || _deadline >= block.timestamp, "GaslessAsksV1::fillSignedAsk deadline expired");

        bytes32 hashStruct = keccak256(abi.encode(SIGNED_ASK_TYPEHASH, _seller, _tokenContract, _tokenId, _askPrice, _deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", EIP_712_DOMAIN_SEPARATOR, hashStruct));
        address recoveredAddress = ecrecover(digest, _v, _r, _s);
        require(recoveredAddress != address(0) && recoveredAddress == _seller, "GaslessAsksV1::fillSignedAsk invalid signature");

        require(IERC721(_tokenContract).ownerOf(_tokenId) == _seller, "GaslessAsksV1::fillSignedAsk seller must own token");
        require(erc721TransferHelper.isModuleApproved(_seller), "GaslessAsksV1::fillSignedAsk must approve GaslessAsksV1 module");
        require(
            IERC721(_tokenContract).isApprovedForAll(_seller, address(erc721TransferHelper)),
            "GaslessAsksV1::fillSignedAsk must approve ERC721TransferHelper as operator"
        );
        require(msg.value == _askPrice, "GaslessAsksV1::fillSignedAsk msg value must equal ask price");

        erc721TransferHelper.transferFrom(_tokenContract, _seller, msg.sender, _tokenId);
        _handleOutgoingTransfer(_seller, _askPrice, address(0), USE_ALL_GAS_FLAG);

        ExchangeDetails memory userAExchangeDetails = ExchangeDetails({tokenContract: _tokenContract, tokenId: _tokenId, amount: 1});
        ExchangeDetails memory userBExchangeDetails = ExchangeDetails({tokenContract: address(0), tokenId: 0, amount: _askPrice});
        emit ExchangeExecuted(ask.seller, msg.sender, userAExchangeDetails, userBExchangeDetails);
        emit AskFilled(_tokenContract, _tokenId, _askPrice, msg.sender, _seller);
    }
}
