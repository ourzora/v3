// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {DSTest} from "ds-test/test.sol";

import {IAsksGaslessEth, AsksGaslessEth} from "../../../../../modules/Asks/Gasless/ETH/AsksGaslessEth.sol";
import {Zorb} from "../../../../utils/users/Zorb.sol";
import {ZoraRegistrar} from "../../../../utils/users/ZoraRegistrar.sol";
import {ZoraModuleManager} from "../../../../../ZoraModuleManager.sol";
import {ZoraProtocolFeeSettings} from "../../../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
import {ERC20TransferHelper} from "../../../../../transferHelpers/ERC20TransferHelper.sol";
import {ERC721TransferHelper} from "../../../../../transferHelpers/ERC721TransferHelper.sol";
import {RoyaltyEngine} from "../../../../utils/modules/RoyaltyEngine.sol";
import {TestERC721} from "../../../../utils/tokens/TestERC721.sol";
import {WETH} from "../../../../utils/tokens/WETH.sol";
import {VM} from "../../../../utils/VM.sol";

/// @title Asks Gasless ETH
/// @notice Unit Tests for Asks Gasless ETH
contract AsksGaslessEthTest is DSTest {
    VM internal vm;

    ZoraRegistrar internal registrar;
    ZoraProtocolFeeSettings internal ZPFS;
    ZoraModuleManager internal ZMM;
    ERC20TransferHelper internal erc20TransferHelper;
    ERC721TransferHelper internal erc721TransferHelper;
    RoyaltyEngine internal royaltyEngine;

    AsksGaslessEth internal asks;
    WETH internal weth;
    TestERC721 internal token;

    uint256 internal privateKey = 0xABCDEF;
    address internal seller;

    Zorb internal buyer;
    Zorb internal royaltyRecipient;

    function setUp() public {
        // Cheatcodes
        vm = VM(HEVM_ADDRESS);

        // Deploy V3
        registrar = new ZoraRegistrar();
        ZPFS = new ZoraProtocolFeeSettings();
        ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
        erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
        erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

        // Init V3
        registrar.init(ZMM);
        ZPFS.init(address(ZMM), address(0));

        // Create users
        seller = vm.addr(privateKey);
        buyer = new Zorb(address(ZMM));
        royaltyRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Asks Gasless ETH
        asks = new AsksGaslessEth(address(ZMM), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

        // Set buyer balance
        vm.deal(address(buyer), 100 ether);

        // Mint seller token
        token.mint(seller, 1);

        // Seller approve ERC721TransferHelper
        vm.prank(seller);
        token.setApprovalForAll(address(erc721TransferHelper), true);
    }

    ///                                                          ///
    ///                          UTILS                           ///
    ///                                                          ///

    function test_GetHash() public {
        bytes32 sigHash = keccak256(
            "SignedAsk(address tokenContract,uint256 tokenId,uint256 expiry,uint256 nonce, uint256 price,uint8 _v,bytes32 _r,bytes32 _s,uint256 deadline)"
        );

        emit log_bytes32(sigHash);
    }

    function getModuleApprovalSig() public returns (IAsksGaslessEth.ModuleApprovalSig memory) {
        bytes32 ZMM_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA")),
                keccak256(bytes("3")),
                99,
                address(ZMM)
            )
        );

        // keccak256("SignedApproval(address module,address user,bool approved,uint256 deadline,uint256 nonce)")
        bytes32 SIGNED_APPROVAL = 0x8413132cc7aa5bd2ce1a1b142a3f09e2baeda86addf4f9a5dacd4679f56e7cec;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(abi.encodePacked("\x19\x01", ZMM_DOMAIN_SEPARATOR, keccak256(abi.encode(SIGNED_APPROVAL, address(asks), seller, true, 0, 0))))
        );

        IAsksGaslessEth.ModuleApprovalSig memory sig = IAsksGaslessEth.ModuleApprovalSig({v: v, r: r, s: s, deadline: 0});

        return sig;
    }

    function getSignedAskSig()
        public
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 ASKS_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA:AsksGaslessEth")),
                keccak256(bytes("1")),
                99,
                address(asks)
            )
        );

        // keccak256("SignedAsk(address tokenContract,uint256 tokenId,uint256 expiry,uint256 nonce, uint256 price,uint8 _v,bytes32 _r,bytes32 _s,uint256 deadline)");
        bytes32 ASK_APPROVAL = 0xde0428517acbd93d05cf529384fe8d583dfcab25db4370d93bcece3b3bc85629;

        IAsksGaslessEth.ModuleApprovalSig memory sig = getModuleApprovalSig();

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ASKS_DOMAIN_SEPARATOR,
                    keccak256(abi.encode(ASK_APPROVAL, address(token), 1, 0, 0, 1 ether, sig.v, sig.r, sig.s, 0))
                )
            )
        );
    }

    function getSignedAskSigWithoutModuleApproval()
        public
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 ASKS_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ZORA:AsksGaslessEth")),
                keccak256(bytes("1")),
                99,
                address(asks)
            )
        );

        // keccak256("SignedAsk(address tokenContract,uint256 tokenId,uint256 expiry,uint256 nonce, uint256 price,uint8 _v,bytes32 _r,bytes32 _s,uint256 deadline)");
        bytes32 ASK_APPROVAL = 0xde0428517acbd93d05cf529384fe8d583dfcab25db4370d93bcece3b3bc85629;

        IAsksGaslessEth.ModuleApprovalSig memory sig = IAsksGaslessEth.ModuleApprovalSig({v: 0, r: 0, s: 0, deadline: 0});

        (v, r, s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ASKS_DOMAIN_SEPARATOR,
                    keccak256(abi.encode(ASK_APPROVAL, address(token), 1, 0, 0, 1 ether, sig.v, sig.r, sig.s, 0))
                )
            )
        );
    }

    ///                                                          ///
    ///                         FILL ASK                         ///
    ///                                                          ///

    function test_FillAskWithModuleApprovalSig() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(ask, v, r, s);

        require(token.ownerOf(1) == address(buyer));
    }

    function test_FillAskWithEmptyApprovalSig() public {
        vm.prank(seller);
        ZMM.setApprovalForModule(address(asks), true);

        IAsksGaslessEth.ModuleApprovalSig memory sig = IAsksGaslessEth.ModuleApprovalSig({v: 0, r: 0, s: 0, deadline: 0});

        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: sig
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSigWithoutModuleApproval();

        vm.prank(address(buyer));
        asks.fillAsk{value: 1 ether}(ask, v, r, s);

        require(token.ownerOf(1) == address(buyer));
    }

    function testRevert_ExpiredAsk() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 1 days,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        vm.warp(1 days + 1 minutes);

        vm.prank(address(buyer));
        vm.expectRevert("EXPIRED_ASK");
        asks.fillAsk{value: 1 ether}(ask, v, r, s);
    }

    function testRevert_InvalidSig() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        vm.prank(address(buyer));
        vm.expectRevert("INVALID_SIG");
        asks.fillAsk{value: 1 ether}(ask, v - 1, r, s);
    }

    function testRevert_InvalidAsk() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        vm.prank(seller);
        asks.cancelAsk(ask);

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        vm.prank(address(buyer));
        vm.expectRevert("INVALID_ASK");
        asks.fillAsk{value: 1 ether}(ask, v, r, s);
    }

    function testRevert_MatchPrice() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        vm.prank(address(buyer));
        vm.expectRevert("MUST_MATCH_PRICE");
        asks.fillAsk{value: 0.9 ether}(ask, v, r, s);
    }

    ///                                                          ///
    ///                        CANCEL ASK                        ///
    ///                                                          ///

    function test_CancelAsk() public {
        require(asks.nonce(address(token), 1) == 0);

        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        vm.prank(seller);
        asks.cancelAsk(ask);

        require(asks.nonce(address(token), 1) == 1);
    }

    function testRevert_OnlySeller() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        vm.expectRevert("ONLY_SIGNER");
        asks.cancelAsk(ask);
    }

    ///                                                          ///
    ///                       VALIDATE ASK                       ///
    ///                                                          ///

    function test_ValidateAsk() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSig();

        bool valid = asks.validateAskSig(ask, v, r, s);

        require(valid);
    }

    function testRevert_InvalidSigner() public {
        IAsksGaslessEth.GaslessAsk memory ask = IAsksGaslessEth.GaslessAsk({
            seller: seller,
            tokenContract: address(token),
            tokenId: 1,
            expiry: 0,
            nonce: 0,
            price: 1 ether,
            approvalSig: getModuleApprovalSig()
        });

        (uint8 v, bytes32 r, bytes32 s) = getSignedAskSigWithoutModuleApproval();

        bool valid = asks.validateAskSig(ask, v, r, s);

        require(!valid);
    }
}
