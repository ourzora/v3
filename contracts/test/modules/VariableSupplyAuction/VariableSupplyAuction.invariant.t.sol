// TODO setup actor-based target senders and implement remaining invariants
// 
// // SPDX-License-Identifier: GPL-3.0
// pragma solidity 0.8.10;

// import {VariableSupplyAuction} from "../../../modules/VariableSupplyAuction/VariableSupplyAuction.sol";

// import {ERC721Drop} from "../../../modules/VariableSupplyAuction/temp-MockERC721Drop.sol";
// import {Zorb} from "../../utils/users/Zorb.sol";
// import {ZoraRegistrar} from "../../utils/users/ZoraRegistrar.sol";
// import {ZoraModuleManager} from "../../../ZoraModuleManager.sol";
// import {ZoraProtocolFeeSettings} from "../../../auxiliary/ZoraProtocolFeeSettings/ZoraProtocolFeeSettings.sol";
// import {ERC20TransferHelper} from "../../../transferHelpers/ERC20TransferHelper.sol";
// import {ERC721TransferHelper} from "../../../transferHelpers/ERC721TransferHelper.sol";
// import {RoyaltyEngine} from "../../utils/modules/RoyaltyEngine.sol";
// import {TestERC721} from "../../utils/tokens/TestERC721.sol";
// import {WETH} from "../../utils/tokens/WETH.sol";
// import {InvariantTest} from "../../utils/InvariantTest.sol";
// import {VM} from "../../utils/VM.sol";

// /// @title VariableSupplyAuctionTest
// /// @notice Invariant Tests for Variable Supply Auctions
// contract VariableSupplyAuctionInvariantTest is InvariantTest {
// //

//     ZoraRegistrar internal registrar;
//     ZoraProtocolFeeSettings internal ZPFS;
//     ZoraModuleManager internal ZMM;
//     // ERC20TransferHelper internal erc20TransferHelper;
//     ERC721TransferHelper internal erc721TransferHelper;
//     RoyaltyEngine internal royaltyEngine;

//     VariableSupplyAuction internal auctions;
//     ERC721Drop internal drop;
//     WETH internal weth;

//     Zorb internal seller;
//     Zorb internal sellerFundsRecipient;
//     Zorb internal operator;
//     Zorb internal finder;
//     Zorb internal royaltyRecipient;
//     Zorb internal bidder1;
//     Zorb internal bidder2;
//     Zorb internal bidder3;
//     Zorb internal bidder4;
//     Zorb internal bidder5;
//     Zorb internal bidder6;
//     Zorb internal bidder7;
//     Zorb internal bidder8;
//     Zorb internal bidder9;
//     Zorb internal bidder10;
//     Zorb internal bidder11;
//     Zorb internal bidder12;
//     Zorb internal bidder13;
//     Zorb internal bidder14;
//     Zorb internal bidder15;

//     string internal constant salt1 = "setec astronomy";
//     string internal constant salt2 = "too many secrets";
//     string internal constant salt3 = "cray tomes on set";
//     string internal constant salt4 = "o no my tesseract";
//     string internal constant salt5 = "ye some contrast";
//     string internal constant salt6 = "a tron ecosystem";
//     string internal constant salt7 = "stonecasty rome";
//     string internal constant salt8 = "coy teamster son";
//     string internal constant salt9 = "cyanometer toss";
//     string internal constant salt10 = "cementatory sos";
//     string internal constant salt11 = "my cotoneasters";
//     string internal constant salt12 = "ny sec stateroom";
//     string internal constant salt13 = "oc attorney mess";
//     string internal constant salt14 = "my cots earstones";
//     string internal constant salt15 = "easternmost coy";

//     function setUp() public {
//         // Deploy V3
//         registrar = new ZoraRegistrar();
//         ZPFS = new ZoraProtocolFeeSettings();
//         ZMM = new ZoraModuleManager(address(registrar), address(ZPFS));
//         // erc20TransferHelper = new ERC20TransferHelper(address(ZMM));
//         erc721TransferHelper = new ERC721TransferHelper(address(ZMM));

//         // Init V3
//         registrar.init(ZMM);
//         ZPFS.init(address(ZMM), address(0));

//         // Create users
//         seller = new Zorb(address(ZMM));
//         sellerFundsRecipient = new Zorb(address(ZMM));
//         operator = new Zorb(address(ZMM));
//         bidder1 = new Zorb(address(ZMM));
//         bidder2 = new Zorb(address(ZMM));
//         bidder3 = new Zorb(address(ZMM));
//         bidder4 = new Zorb(address(ZMM));
//         bidder5 = new Zorb(address(ZMM));
//         bidder6 = new Zorb(address(ZMM));
//         bidder7 = new Zorb(address(ZMM));
//         bidder8 = new Zorb(address(ZMM));
//         bidder9 = new Zorb(address(ZMM));
//         bidder10 = new Zorb(address(ZMM));
//         bidder11 = new Zorb(address(ZMM));
//         bidder12 = new Zorb(address(ZMM));
//         bidder13 = new Zorb(address(ZMM));
//         bidder14 = new Zorb(address(ZMM));
//         bidder15 = new Zorb(address(ZMM));
//         finder = new Zorb(address(ZMM));
//         royaltyRecipient = new Zorb(address(ZMM));

//         // Set balances
//         vm.deal(address(seller), 100 ether);
//         vm.deal(address(bidder1), 100 ether);
//         vm.deal(address(bidder2), 100 ether);
//         vm.deal(address(bidder3), 100 ether);
//         vm.deal(address(bidder4), 100 ether);
//         vm.deal(address(bidder5), 100 ether);
//         vm.deal(address(bidder6), 100 ether);
//         vm.deal(address(bidder7), 100 ether);
//         vm.deal(address(bidder8), 100 ether);
//         vm.deal(address(bidder9), 100 ether);
//         vm.deal(address(bidder10), 100 ether);
//         vm.deal(address(bidder11), 100 ether);
//         vm.deal(address(bidder12), 100 ether);
//         vm.deal(address(bidder13), 100 ether);
//         vm.deal(address(bidder14), 100 ether);
//         vm.deal(address(bidder15), 100 ether);

//         // Deploy mocks
//         royaltyEngine = new RoyaltyEngine(address(royaltyRecipient));
//         drop = new ERC721Drop();
//         drop.initialize({
//             _contractName: "Test Mutant Ninja Turtles",
//             _contractSymbol: "TMNT",
//             _initialOwner: address(seller),
//             _fundsRecipient: payable(sellerFundsRecipient),
//             _editionSize: 1,
//             _royaltyBPS: 1000
//             // _metadataRenderer: dummyRenderer,
//             // _metadataRendererInit: "",
//             // _salesConfig: IERC721Drop.SalesConfiguration({
//             //     publicSaleStart: 0,
//             //     publicSaleEnd: 0,
//             //     presaleStart: 0,
//             //     presaleEnd: 0,
//             //     publicSalePrice: 0,
//             //     maxSalePurchasePerAddress: 0,
//             //     presaleMerkleRoot: bytes32(0)
//             // })
//         });
//         weth = new WETH();

//         // Deploy Variable Supply Auction module
//         auctions = new VariableSupplyAuction(address(erc721TransferHelper), address(royaltyEngine), address(ZPFS), address(weth));
//         registrar.registerModule(address(auctions));

//         // Grant auction minter role on drop contract
//         vm.prank(address(seller));
//         drop.grantRole(drop.MINTER_ROLE(), address(auctions));

//         // Users approve module
//         seller.setApprovalForModule(address(auctions), true);
//         bidder1.setApprovalForModule(address(auctions), true);
//         bidder2.setApprovalForModule(address(auctions), true);
//         bidder3.setApprovalForModule(address(auctions), true);
//         bidder4.setApprovalForModule(address(auctions), true);
//         bidder5.setApprovalForModule(address(auctions), true);
//         bidder6.setApprovalForModule(address(auctions), true);
//         bidder7.setApprovalForModule(address(auctions), true);
//         bidder8.setApprovalForModule(address(auctions), true);
//         bidder9.setApprovalForModule(address(auctions), true);
//         bidder10.setApprovalForModule(address(auctions), true);
//         bidder11.setApprovalForModule(address(auctions), true);
//         bidder12.setApprovalForModule(address(auctions), true);
//         bidder13.setApprovalForModule(address(auctions), true);
//         bidder14.setApprovalForModule(address(auctions), true);
//         bidder15.setApprovalForModule(address(auctions), true);

//         // Seller approve ERC721TransferHelper
//         // vm.prank(address(seller));
//         // token.setApprovalForAll(address(erc721TransferHelper), true);

//         // Setup invariant targets
//         excludeContract(address(registrar));
//         excludeContract(address(ZPFS));
//         excludeContract(address(ZMM));
//         excludeContract(address(erc721TransferHelper));

//         excludeContract(address(royaltyEngine));
//         excludeContract(address(drop));
//         excludeContract(address(weth));

//         excludeContract(address(seller));
//         excludeContract(address(sellerFundsRecipient));
//         excludeContract(address(operator));
//         excludeContract(address(finder));
//         excludeContract(address(royaltyRecipient));

//         excludeContract(address(bidder1));
//         excludeContract(address(bidder2));
//         excludeContract(address(bidder3));
//         excludeContract(address(bidder4));
//         excludeContract(address(bidder5));
//         excludeContract(address(bidder6));
//         excludeContract(address(bidder7));
//         excludeContract(address(bidder8));
//         excludeContract(address(bidder9));
//         excludeContract(address(bidder10));
//         excludeContract(address(bidder12));
//         excludeContract(address(bidder13));
//         excludeContract(address(bidder14));
//         excludeContract(address(bidder15));

//         targetContract(address(auctions));

//         

//         // Setup one auction
//         vm.prank(address(seller));
//         auctions.createAuction({
//             _tokenContract: address(drop),
//             _minimumViableRevenue: 1 ether,
//             _sellerFundsRecipient: address(sellerFundsRecipient),
//             _startTime: block.timestamp,
//             _bidPhaseDuration: 3 days,
//             _revealPhaseDuration: 2 days,
//             _settlePhaseDuration: 1 days
//         });
//     }

//     

//     // function invariant_true_eq_true() public {
//     //     assertTrue(true);
//     // }

//     // function invariant_auctionTotalBalance_lt_1ether() public {
//     //     (
//     //         address sellerStored,
//     //         uint256 minimumRevenue,
//     //         address sellerFundsRecipientStored,
//     //         uint256 startTime,
//     //         uint256 endOfBidPhase,
//     //         uint256 endOfRevealPhase,
//     //         uint256 endOfSettlePhase,
//     //         uint96 totalBalance
//     //     ) = auctions.auctionForDrop(address(drop));

//     //     assertLt(totalBalance, 1 ether);
//     // }
// }
