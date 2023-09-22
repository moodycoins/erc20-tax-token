// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {MockV2Router} from "./MockV2Router.sol";
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
