// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Script.sol";
import "./ReserveAuctionListingAdjustableBufferIncrementEth.sol";

contract Deploy is Script {
    address public constant erc721TransferHelper = 0x909e9efE4D87d1a6018C2065aE642b6D0447bc91;
    address public constant royaltyEngine = 0x0385603ab55642cb4dd5de3ae9e306809991804f;
    address public constant protocolFeeSettings = 0x9641169A1374b77E052E1001c5a096C29Cd67d35;
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        ReserveAuctionListingAdjustableBufferIncrementEth auctions = new ReserveAuctionListingAdjustableBufferIncrementEth(
            erc721TransferHelper,
            royaltyEngine,
            protocolFeeSettings,
            weth
        );

        vm.stopBroadcast();
    }
}
