// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

contract MockV2Router {
    address public constant WETH = address(0xEEE);
    address public immutable factory = address(this);

    function createPair(address, address) public pure returns (address) {
        return address(0xdEaD);
    }
}