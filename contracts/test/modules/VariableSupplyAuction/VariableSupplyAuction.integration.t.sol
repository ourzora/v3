// TODO move large settleAuction unit tests here and simplify the test scenarios there
//
// // SPDX-License-Identifier: GPL-3.0
// pragma solidity 0.8.10;

// import {DSTest} from "ds-test/test.sol";

// import {VariableSupplyAuction} from "../../../modules/VariableSupplyAuction/VariableSupplyAuction.sol";
// import {Zorb} from "../../utils/users/Zorb.sol";
// import {ZoraRegistrar} from "../../utils/users/ZoraRegistrar.sol";
// import {ZoraModuleManager} from "../../../ZoraModuleManager.sol";
// import {ZoraProtocolFeeSettings} from "../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
// import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
// import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
// import {RoyaltyEngine} from "../../utils/modules/RoyaltyEngine.sol";
// import {TestERC721} from "../../utils/tokens/TestERC721.sol";
// import {WETH} from "../../utils/tokens/WETH.sol";
// import {VM} from "../../utils/VM.sol";

// /// @title VariableSupplyAuctionIntegrationTest
// /// @notice Integration Tests for Variable Supply Auctions
// contract VariableSupplyAuctionIntegrationTest is DSTest {
//     //
//     VM internal vm;

//     ZoraRegistrar internal registrar;
//     ZoraProtocolFeeSettings internal ZPFS;
//     ZoraModuleManager internal ZMM;
//     ERC20TransferHelper internal erc20TransferHelper;
//     ERC721TransferHelper internal erc721TransferHelper;
//     RoyaltyEngine internal royaltyEngine;

//     VariableSupplyAuction internal auctions;
//     TestERC721 internal token;
//     WETH internal weth;

//     Zorb internal seller;
//     Zorb internal sellerFundsRecipient;
//     Zorb internal finder;
//     Zorb internal royaltyRecipient;
//     Zorb internal bidder;
//     Zorb internal otherBidder;
//     Zorb internal protocolFeeRecipient;

//     function setUp() public {
//         // Cheatcodes
//         vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

//         // Deploy V3
//         registrar = new ZoraRegistrar();
//         ZPFS = new ZoraProtocolFeeSettings();
//         ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
//         erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
//         erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

//         // Init V3
//         registrar.init(ZMM);
//         ZPFS.init(address(ZMM), address(0));

//         // Create users
//         seller = new Zorb(address(ZMM));
//         sellerFundsRecipient = new Zorb(address(ZMM));
//         bidder = new Zorb(address(ZMM));
//         otherBidder = new Zorb(address(ZMM));
//         royaltyRecipient = new Zorb(address(ZMM));
//         protocolFeeRecipient = new Zorb(address(ZMM));

//         // Deploy mocks
//         royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
//         token = new TestERC721();
//         weth = new WETH();

//         // Deploy Reserve Auction Core ETH
//         auctions = new VariableSupplyAuction(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
//         registrar.registerModule(address(auctions));

//         // Set module fee
//         vm.prank(address(registrar));
//         ZPFS.setFeeParams(address(auctions), address(protocolFeeRecipient), 1);

//         // Set balances
//         vm.deal(address(seller), 100 ether);
//         vm.deal(address(bidder), 100 ether);
//         vm.deal(address(otherBidder), 100 ether);

//         // Mint seller token
//         token.mint(address(seller), 1);

//         // Bidder swap 50 ETH <> 50 WETH
//         vm.prank(address(bidder));
//         weth.deposit{value: 50 ether}();

//         // otherBidder swap 50 ETH <> 50 WETH
//         vm.prank(address(otherBidder));
//         weth.deposit{value: 50 ether}();

//         // Users approve ReserveAuction module
//         seller.setApprovalForModule(address(auctions), true);
//         bidder.setApprovalForModule(address(auctions), true);
//         otherBidder.setApprovalForModule(address(auctions), true);

//         // Seller approve ERC721TransferHelper
//         vm.prank(address(seller));
//         token.setApprovalForAll(address(erc721TransferHelper), true);

//         // Bidder approve ERC20TransferHelper
//         vm.prank(address(bidder));
//         weth.approve(address(erc20TransferHelper), 50 ether);

//         // otherBidder approve ERC20TransferHelper
//         vm.prank(address(otherBidder));
//         weth.approve(address(erc20TransferHelper), 50 ether);
//     }

//     

//     function runETH() public {
//         //
//     }

//     function test_ETHIntegration() public {
//         uint256 beforeSellerBalance = address(sellerFundsRecipient).balance;
//         uint256 beforeBidderBalance = address(bidder).balance;
//         uint256 beforeOtherBidderBalance = address(otherBidder).balance;
//         uint256 beforeRoyaltyRecipientBalance = address(royaltyRecipient).balance;
//         uint256 beforeProtocolFeeRecipient = address(protocolFeeRecipient).balance;
//         address beforeTokenOwner = token.ownerOf(1);

//         runETH();

//         uint256 afterSellerBalance = address(sellerFundsRecipient).balance;
//         uint256 afterBidderBalance = address(bidder).balance;
//         uint256 afterOtherBidderBalance = address(otherBidder).balance;
//         uint256 afterRoyaltyRecipientBalance = address(royaltyRecipient).balance;
//         uint256 afterProtocolFeeRecipient = address(protocolFeeRecipient).balance;
//         address afterTokenOwner = token.ownerOf(1);

//         assertEq(beforeSellerBalance, afterSellerBalance);
//     }
// }
