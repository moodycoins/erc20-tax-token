// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20SwapTax} from "../../src/ERC20SwapTax.sol";

// Contract for testing basic ERC20 functionality
contract MockERC20SwapTax is ERC20SwapTax {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20SwapTax(_name, _symbol, 0, address(new MockV2Router()), address(0xBEEF), 1, 1, 1, false, false) {
    }

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}

contract MockV2Router {
    address public constant WETH = address(0xEEE);
    address public immutable factory = address(this);

    function createPair(address, address) public pure returns (address) {
        return address(0xFEFE);
    }
}
