// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

/**
 * @notice A library for manipulation of byte arrays.
 */
library BytesLibrary {
    /**
     * @dev Replace the address at the given location in a byte array if the contents at that location
     * match the expected address.
     */
    function replaceAtIf(
        bytes memory data,
        uint256 startLocation,
        address expectedAddress,
        address newAddress
    ) internal pure {
        bytes memory expectedData = abi.encodePacked(expectedAddress);
        bytes memory newData = abi.encodePacked(newAddress);
        // An address is 20 bytes long
        for (uint256 i = 0; i < 20; i++) {
            uint256 dataLocation = startLocation + i;
            require(data[dataLocation] == expectedData[i], "Bytes: Data provided does not include the expectedAddress");
            data[dataLocation] = newData[i];
        }
    }

    /**
     * @dev Checks if the call data starts with the given function signature.
     */
    function startsWith(bytes memory callData, bytes4 functionSig) internal pure returns (bool) {
        // A signature is 4 bytes long
        if (callData.length < 4) {
            return false;
        }
        for (uint256 i = 0; i < 4; i++) {
            if (callData[i] != functionSig[i]) {
                return false;
            }
        }

        return true;
    }
}
