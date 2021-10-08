// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.5;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract DividendsImplementationV1 is Initializable {
    // The ERC-721 address for the community receiving dividends
    ERC721Enumerable public nft;
    // The total amount of received dividends
    uint256 public totalIncome;
    // The next withdrawal base for each token ID
    mapping(uint256 => uint256) public nextWithdrawalBase;

    event DividendsClaimed(address indexed recipient, uint256 indexed tokenID, uint256 amount);
    event FundsReceived(uint256 amount);

    function initialize(address _nftAddress) public initializer {
        nft = ERC721Enumerable(_nftAddress);

        require(nft.supportsInterface(type(IERC721Enumerable).interfaceId), "initialize supplied NFT does not support IERC721Enumerable interface");
    }

    // The amount of funds available to be claimed for the token
    function claimableDividendsForToken(uint256 _tokenID) public view returns (uint256) {
        return (totalIncome - nextWithdrawalBase[_tokenID]) / nft.totalSupply();
    }

    // Claim dividends for a token, distributing the funds to the current owner
    function claimDividendsForToken(uint256 _tokenID) public {
        address recipient = nft.ownerOf(_tokenID);
        uint256 amount = claimableDividendsForToken(_tokenID);

        // Attempt to transfer the claimable dividends to the owner of the token
        (bool success, ) = recipient.call{value: amount}(new bytes(0));
        require(success, "claimDividendsForToken recipient could not receive ETH");

        // Set the nextWithdrawalBase for the token
        nextWithdrawalBase[_tokenID] = totalIncome;

        emit DividendsClaimed(recipient, _tokenID, amount);
    }

    receive() external payable {
        totalIncome += msg.value;

        emit FundsReceived(msg.value);
    }
}
