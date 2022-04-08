// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.10;

interface VM {
    /// @dev Set block.timestamp (newTimestamp)
    function warp(uint256) external;

    /// @dev Set block.height (newHeight)
    function roll(uint256) external;

    /// @dev Loads a storage slot from an address (who, slot)
    function load(address, bytes32) external returns (bytes32);

    /// @dev Stores a value to an address' storage slot, (who, slot, value)
    function store(
        address,
        bytes32,
        bytes32
    ) external;

    /// @dev Signs data, (privateKey, digest) => (r, v, s)
    function sign(uint256, bytes32)
        external
        returns (
            uint8,
            bytes32,
            bytes32
        );

    /// @dev Gets address for a given private key, (privateKey) => (address)
    function addr(uint256) external returns (address);

    /// @dev Performs a foreign function call via terminal, (stringInputs) => (result)
    function ffi(string[] calldata) external returns (bytes memory);

    /// @dev Performs the next smart contract call with specified `msg.sender`, (newSender)
    function prank(address) external;

    /// @dev Performs all the following smart contract calls with specified `msg.sender`, (newSender)
    function startPrank(address) external;

    /// @dev Stop smart contract calls using the specified address with startPrank()
    function stopPrank() external;

    /// @dev Sets an address' balance, (who, newBalance)
    function deal(address, uint256) external;

    /// @dev Sets an address' code, (who, newCode)
    function etch(address, bytes calldata) external;

    /// @dev Expects an error on next call
    function expectRevert(bytes calldata) external;

    /// @dev Expects the next emitted event. Params check topic 1, topic 2, topic 3 and data are the same.
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    /// @dev Mocks a call to an address, returning specified data.
    /// Calldata can either be strict or a partial match, e.g. if you only
    /// pass a Solidity selector to the expected calldata, then the entire Solidity
    /// function will be mocked.
    function mockCall(
        address,
        bytes calldata,
        bytes calldata
    ) external;

    /// @dev Clears all mocked calls
    function clearMockedCalls() external;

    /// @dev Expect a call to an address with the specified calldata.
    /// @dev Calldata can either be strict or a partial match
    function expectCall(address, bytes calldata) external;
}
