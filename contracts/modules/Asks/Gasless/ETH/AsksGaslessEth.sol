// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {ERC721TransferHelper} from "../../../../transferHelpers/ERC721TransferHelper.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {IAsksGaslessEth} from "./IAsksGaslessEth.sol";

/// @title Asks Gasless ETH
/// @author tbtstl & kulkarohan
/// @notice Module for gasless ETH asks for ERC-721 tokens, providing off-chain order support
contract AsksGaslessEth is ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                       MODULE SETUP                       ///
    ///                                                          ///

    /// @notice The ZORA ERC-721 Transfer Helper
    ERC721TransferHelper public immutable erc721TransferHelper;

    /// @notice The ZORA Module Manager
    ZoraModuleManager public immutable ZMM;

    /// @param _zmm The ZORA Module Manager
    /// @param _erc721TransferHelper The ZORA ERC-721 Transfer Helper address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    constructor(
        address _zmm,
        address _erc721TransferHelper,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ERC721TransferHelper(_erc721TransferHelper).ZMM().registrar())
        ModuleNamingSupportV1("Asks Gasless ETH")
    {
        ZMM = ZoraModuleManager(_zmm);
        erc721TransferHelper = ERC721TransferHelper(_erc721TransferHelper);
    }

    ///                                                          ///
    ///                          EIP-165                         ///
    ///                                                          ///

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IAsksGaslessEth).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    ///                                                          ///
    ///                          EIP-712                         ///
    ///                                                          ///

    /// @notice The EIP-712 type for a signed ask order
    /// @dev keccak256("SignedAsk(address tokenContract,uint256 tokenId,uint256 expiry,uint256 nonce, uint256 price,uint8 _v,bytes32 _r,bytes32 _s,uint256 deadline)");
    bytes32 private constant SIGNED_ASK_TYPEHASH = 0xde0428517acbd93d05cf529384fe8d583dfcab25db4370d93bcece3b3bc85629;

    /// @notice The EIP-712 domain separator
    bytes32 private immutable EIP_712_DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA:AsksGaslessEth")),
                keccak256(bytes("1")),
                _chainID(),
                address(this)
            )
        );

    /// @notice The EIP-155 chain id
    function _chainID() private view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    /// @notice Recovers the signer of the ask
    /// @param _ask The signed gasless ask
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function _recoverAddress(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) private view returns (address) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                EIP_712_DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        SIGNED_ASK_TYPEHASH,
                        _ask.tokenContract,
                        _ask.tokenId,
                        _ask.expiry,
                        _ask.nonce,
                        _ask.price,
                        _ask.approvalSig.v,
                        _ask.approvalSig.r,
                        _ask.approvalSig.s,
                        _ask.approvalSig.deadline
                    )
                )
            )
        );

        return ecrecover(digest, _v, _r, _s);
    }

    ///                                                          ///
    ///                        ASK STORAGE                       ///
    ///                                                          ///

    /// @notice The number of filled or canceled asks for a given token
    /// @dev ERC-721 address => ERC-721 id
    mapping(address => mapping(uint256 => uint256)) public nonce;

    ///                                                          ///
    ///                         FILL ASK                         ///
    ///                                                          ///

    /// @notice Emitted when a signed ask is filled
    /// @param ask The metadata of the ask
    /// @param buyer The address of the buyer
    event AskFilled(IAsksGaslessEth.GaslessAsk ask, address buyer);

    /// @notice Fills the given signed ask for an NFT
    /// @param _ask The signed ask to fill
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function fillAsk(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable nonReentrant {
        // Ensure the ask has not expired
        require(_ask.expiry == 0 || _ask.expiry >= block.timestamp, "EXPIRED_ASK");

        // Recover the signer address
        address recoveredAddress = _recoverAddress(_ask, _v, _r, _s);

        // Cache the seller address
        address seller = _ask.seller;

        // Ensure the recovered signer matches the seller
        require(recoveredAddress == seller, "INVALID_SIG");

        // Cache the token contract
        address tokenContract = _ask.tokenContract;

        // Cache the token id
        uint256 tokenId = _ask.tokenId;

        // Ensure the ask nonce matches the token nonce
        require(_ask.nonce == nonce[tokenContract][tokenId], "INVALID_ASK");

        // Ensure the attached ETH matches the price
        require(msg.value == _ask.price, "MUST_MATCH_PRICE");

        // If the seller has not approved this module in the ZORA Module Manager,
        if (!ZMM.isModuleApproved(seller, address(this))) {
            // Approve the module on behalf of the seller
            ZMM.setApprovalForModuleBySig(
                address(this),
                seller,
                true,
                _ask.approvalSig.deadline,
                _ask.approvalSig.v,
                _ask.approvalSig.r,
                _ask.approvalSig.s
            );
        }

        // Payout associated token royalties, if any
        (uint256 remainingProfit, ) = _handleRoyaltyPayout(tokenContract, tokenId, _ask.price, address(0), 300000);

        // Payout the module fee, if configured
        remainingProfit = _handleProtocolFeePayout(remainingProfit, address(0));

        // Transfer the remaining profit to the seller
        _handleOutgoingTransfer(seller, remainingProfit, address(0), 50000);

        // Transfer the NFT to the buyer
        // Reverts if the seller did not approve the ERC721TransferHelper or no longer owns the token
        erc721TransferHelper.transferFrom(tokenContract, seller, msg.sender, tokenId);

        emit AskFilled(_ask, msg.sender);

        // Increment the nonce for the associated token
        // Cannot realistically overflow
        unchecked {
            ++nonce[tokenContract][tokenId];
        }
    }

    ///                                                          ///
    ///                        CANCEL ASK                        ///
    ///                                                          ///

    /// @notice Emitted when an ask is canceled
    /// @param ask The metadata of the ask
    event AskCanceled(IAsksGaslessEth.GaslessAsk ask);

    /// @notice Invalidates an off-chain order
    /// @param _ask The signed ask parameters to invalidate
    function cancelAsk(IAsksGaslessEth.GaslessAsk calldata _ask) external nonReentrant {
        // Ensure the caller is the seller
        require(msg.sender == _ask.seller, "ONLY_SIGNER");

        // Increment the nonce for the associated token
        // Cannot realistically overflow
        unchecked {
            ++nonce[_ask.tokenContract][_ask.tokenId];
        }

        emit AskCanceled(_ask);
    }

    ///                                                          ///
    ///                       BROADCAST ASK                      ///
    ///                                                          ///

    /// @notice Broadcasts an order on-chain to indexers
    /// @dev Intentionally a no-op, this can be picked up via EVM traces :)
    /// @param _ask The signed ask parameters to broadcast
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function broadcastAsk(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // noop :)
    }

    ///                                                          ///
    ///                       VALIDATE ASK                       ///
    ///                                                          ///

    /// @notice Checks if a given signature matches the signer of given ask
    /// @param _ask The signed ask parameters to validate
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    /// @return If the given signature matches the ask signature
    function validateAskSig(
        IAsksGaslessEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external view returns (bool) {
        return _recoverAddress(_ask, _v, _r, _s) == _ask.seller;
    }
}
