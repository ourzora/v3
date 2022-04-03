// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ZoraModuleManager} from "../../../../ZoraModuleManager.sol";
import {FeePayoutSupportV1} from "../../../../common/FeePayoutSupport/FeePayoutSupportV1.sol";
import {ModuleNamingSupportV1} from "../../../../common/ModuleNamingSupport/ModuleNamingSupportV1.sol";
import {IGaslessAsksCoreEth} from "./IGaslessAsksCoreEth.sol";
import {AsksCoreEth} from "./AsksCoreEth.sol";

/// @title Gasless Asks Core ETH
/// @author tbtstl
/// @notice Extension to minimal ETH asks module, providing off-chain order support
contract GaslessAsksCoreEth is IGaslessAsksCoreEth, ReentrancyGuard, FeePayoutSupportV1, ModuleNamingSupportV1 {
    ///                                                          ///
    ///                        IMMUTABLES                        ///
    ///                                                          ///

    ZoraModuleManager private immutable zmm;
    AsksCoreEth private immutable asksModule;

    /// @notice The EIP-712 domain separator
    bytes32 private immutable EIP_712_DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA:GaslessAsksCoreEth")),
                keccak256(bytes("1")),
                _chainID(),
                address(this)
            )
        );

    /// @notice The EIP-712 type for a signed ask order
    /// @dev keccak256("SignedAsk(address tokenAddress,uint256 tokenId,uint256 expiry,uint256 nonce, uint256 amount,uint8 _v,bytes32 _r,bytes32 _s,uint256 deadline)")
    bytes32 private constant SIGNED_ASK_TYPEHASH = 0x324d0f7b7aa4e0f218259028fc60b98a32657c974f8cb44eb3ceadbec042ddc4;

    ///                                                          ///
    ///                        ASK STORAGE                       ///
    ///                                                          ///

    /// @notice The spent (canceled or executed) asks
    /// @dev ERC-721 token contract => ERC-721 token id => Ask signer => spent boolean
    mapping(address => mapping(uint256 => mapping(address => bool))) public spentAsks;

    /// @param _zmm The ZORA Module Manager address
    /// @param _asksModule The ZORA Asks Core ETH Module address
    /// @param _royaltyEngine The Manifold Royalty Engine address
    /// @param _protocolFeeSettings The ZORA Protocol Fee Settings address
    /// @param _weth The WETH token address
    // TODO we don't even need this to be a "module" since no transfer helpers are used here
    constructor(
        address _zmm,
        address _asksModule,
        address _royaltyEngine,
        address _protocolFeeSettings,
        address _weth
    )
        FeePayoutSupportV1(_royaltyEngine, _protocolFeeSettings, _weth, ZoraModuleManager(_zmm).registrar())
        ModuleNamingSupportV1("Gasless Asks Core ETH")
    {
        zmm = ZoraModuleManager(_zmm);
        asksModule = AsksCoreEth(_asksModule);
    }

    /// @notice Implements EIP-165 for standard interface detection
    /// @dev `0x01ffc9a7` is the IERC165 interface id
    /// @param _interfaceId The identifier of a given interface
    /// @return If the given interface is supported
    function supportsInterface(bytes4 _interfaceId) external pure returns (bool) {
        return _interfaceId == type(IGaslessAsksCoreEth).interfaceId || _interfaceId == 0x01ffc9a7;
    }

    /// @notice Executes a signed order on the Asks module
    /// @param _ask The signed ask parameters to execute
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function executeAsk(
        IGaslessAsksCoreEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable nonReentrant {
        require(_ask.expiry == 0 || _ask.expiry >= block.timestamp, "EXPIRED_ASK");
        address recoveredAddress = _recoverAddress(_ask, _v, _r, _s);
        require(recoveredAddress != address(0) && recoveredAddress == _ask.from, "INVALID_SIG");
        require(!spentAsks[_ask.tokenAddress][_ask.tokenId][_ask.from], "SPENT_ASK");

        if (!zmm.isModuleApproved(_ask.from, address(asksModule))) {
            zmm.setApprovalForModuleBySig(
                address(asksModule),
                _ask.from,
                true,
                _ask.approvalSig.deadline,
                _ask.approvalSig.v,
                _ask.approvalSig.r,
                _ask.approvalSig.s
            );
        }

        asksModule.createAsk(_ask.tokenAddress, _ask.tokenId, _ask.amount);
        asksModule.fillAsk{value: msg.value}(_ask.tokenAddress, _ask.tokenId);
        spentAsks[_ask.tokenAddress][_ask.tokenId][_ask.from] = true;

        IERC721(_ask.tokenAddress).transferFrom(address(this), msg.sender, _ask.tokenId);
    }

    /// @notice Creates an on-chain order on the Asks module
    /// @param _ask The signed ask parameters to store
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function storeAsk(
        IGaslessAsksCoreEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        require(_ask.expiry == 0 || _ask.expiry >= block.timestamp, "EXPIRED_ASK");
        address recoveredAddress = _recoverAddress(_ask, _v, _r, _s);
        require(recoveredAddress != address(0) && recoveredAddress == _ask.from, "INVALID_SIG");

        asksModule.createAsk(_ask.tokenAddress, _ask.tokenId, _ask.amount);
    }

    /// @notice Broadcasts an on-chain order to indexers
    /// @dev Intentionally a no-op, this can be picked up via EVM traces :)
    /// @param _ask The signed ask parameters to broadcast
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function broadcastAsk(
        IGaslessAsksCoreEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        // noop :)
    }

    /// @notice Invalidates an off-chain order
    /// @param _ask The signed ask parameters to invalidate
    function cancelAsk(IGaslessAsksCoreEth.GaslessAsk calldata _ask) external nonReentrant {
        require(msg.sender == _ask.from, "ONLY_SIGNER");

        spentAsks[_ask.tokenAddress][_ask.tokenId][msg.sender] = true;
    }

    /// @notice Validates an on-chain order
    /// @param _ask The signed ask parameters to validate
    /// @param _v The 129th byte and chain ID of the signature
    /// @param _r The first 64 bytes of the signature
    /// @param _s Bytes 64-128 of the signature
    function validateAskSig(
        IGaslessAsksCoreEth.GaslessAsk calldata _ask,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external view returns (bool) {
        return _recoverAddress(_ask, _v, _r, _s) == _ask.from;
    }

    function _recoverAddress(
        IGaslessAsksCoreEth.GaslessAsk calldata _ask,
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
                        _ask.tokenAddress,
                        _ask.tokenId,
                        _ask.expiry,
                        _ask.nonce,
                        _ask.amount,
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

    /// @notice The EIP-155 chain id
    function _chainID() private view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }
}
