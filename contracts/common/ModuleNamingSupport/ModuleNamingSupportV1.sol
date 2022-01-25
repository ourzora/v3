// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

/// @title Module Naming Support V1
/// @author kulkarohan <rohan@zora.co>
/// @notice This contract extension supports naming modules
contract ModuleNamingSupportV1 {
    /// @notice The module name
    string public name;

    /// @notice Sets the name of a module
    /// @param _name The module name to set
    constructor(string memory _name) {
        name = _name;
    }
}
