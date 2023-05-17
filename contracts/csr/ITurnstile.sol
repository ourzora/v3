// turnstile address: 0xEcf044C5B4b867CFda001101c617eCd347095B44
// turnstile ID: 22

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface ITurnstile {
    function assign(uint256) external returns (uint256);

    function register(address) external returns (uint256);
}
