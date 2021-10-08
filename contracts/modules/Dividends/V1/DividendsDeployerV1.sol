// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {DividendsImplementationV1} from "./DividendsImplementationV1.sol";

contract DividendsDeployerV1 {
    address public dividendsImplementation;
    mapping(address => address) public nftContractToDividendsContract;

    event DividendsContractDeployed(address indexed NFTContract, address instance);

    constructor(address _dividendsImplementation) {
        dividendsImplementation = _dividendsImplementation;
    }

    // Deploy a dividends clone for a specific NFT address, if one doesn't already exist
    function deployDividendsContract(address _nftContract) public returns (address) {
        require(
            nftContractToDividendsContract[_nftContract] == address(0),
            "deployDividendsContract dividends contract already deployed for given NFT contract"
        );

        address instance = Clones.clone(dividendsImplementation);
        DividendsImplementationV1(payable(instance)).initialize(_nftContract);

        nftContractToDividendsContract[_nftContract] = instance;

        emit DividendsContractDeployed(_nftContract, instance);

        return instance;
    }
}
