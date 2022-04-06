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
/// @notice Integration Tests for Asks Gasless ETH
contract AsksGaslessEthIntegrationTest is DSTest {
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
    Zorb internal protocolFeeRecipient;

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
        protocolFeeRecipient = new Zorb(address(ZMM));

        // Deploy mocks
        royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
        token = new TestERC721();
        weth = new WETH();

        // Deploy Asks Gasless ETH
        asks = new AsksGaslessEth(address(ZMM), address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
        registrar.registerModule(address(asks));

        // Set module fee
        vm.prank(address(registrar));
        ZPFS.setFeeParams(address(asks), address(protocolFeeRecipient), 1);

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

    ///                                                          ///
    ///                      ETH INTEGRATION                     ///
    ///                                                          ///

    function runETH() public {
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
    }

    function test_ETHIntegration() public {
        uint256 beforeBuyerBalance = address(buyer).balance;
        uint256 beforeSellerBalance = address(seller).balance;
        uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 beforeProtocolFeeRecipientBalance = address(protocolFeeRecipient).balance;
        address beforeTokenOwner = token.ownerOf(1);

        runETH();

        uint256 afterBuyerBalance = address(buyer).balance;
        uint256 afterSellerBalance = address(seller).balance;
        uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
        uint256 afterProtocolFeeRecipientBalance = address(protocolFeeRecipient).balance;
        address afterTokenOwner = token.ownerOf(1);

        // 1 ETH withdrawn from buyer
        require((beforeBuyerBalance - afterBuyerBalance) == 1 ether);
        // 0.05 ETH creator royalty
        require((afterRoyaltyRecipientBalance - beforeRoyaltyRecipientBalance) == 0.05 ether);
        // 1 bps protocol fee (Remaining 0.95 ETH * 0.01% protocol fee = 0.000095 ETH)
        require((afterProtocolFeeRecipientBalance - beforeProtocolFeeRecipientBalance) == 0.000095 ether);
        // Remaining 0.949905 ETH paid to seller
        require((afterSellerBalance - beforeSellerBalance) == 0.949905 ether);
        // NFT transferred to buyer
        require(beforeTokenOwner == address(seller) && afterTokenOwner == address(buyer));
    }
}
