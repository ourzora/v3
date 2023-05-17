// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/Clones.sol";

contract ProxyFactory {
    address public immutable implementation;

    event ProxyCreated(address proxy);

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function createProxy() public {
        address clone = Clones.clone(implementation);

        emit ProxyCreated(clone);
    }

    function createProxyAndCall(bytes calldata data) public {
        address clone = Clones.clone(implementation);

        (bool success, ) = clone.call(data);

        require(success, "ProxyFactory: Failed to call function on clone");

        emit ProxyCreated(clone);
    }
}
