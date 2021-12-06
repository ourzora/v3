// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IZoraV1Market {
    struct Decimal {
        uint256 value;
    }

    struct BidShares {
        // % of sale value that goes to the _previous_ owner of the nft
        Decimal prevOwner;
        // % of sale value that goes to the original creator of the nft
        Decimal creator;
        // % of sale value that goes to the seller (current owner) of the nft
        Decimal owner;
    }

    function isValidBid(uint256 tokenId, uint256 bidAmount) external view returns (bool);

    function bidSharesForToken(uint256 tokenId) external view returns (BidShares memory);

    function splitShare(Decimal memory share, uint256 amount) external pure returns (uint256);
}

interface IZoraV1Media is IERC721 {
    function marketContract() external view returns (address);

    function tokenCreators(uint256 tokenId) external view returns (address);

    function previousTokenOwners(uint256 tokenId) external view returns (address);
}
