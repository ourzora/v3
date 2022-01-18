// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

contract ModuleNamingSupportV1 {
    string public name;

    constructor(string memory _name) {
        name = _name;
    }
}
