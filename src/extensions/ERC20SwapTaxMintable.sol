// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20SwapTax} from "../ERC20SwapTax.sol";

/// @title Mintable ERC20 Swap Tax
/// @dev Changing the supply by large amounts can make variables like
/// swapThreshold invalid
contract ERC20SwapTaxMintable is ERC20SwapTax {

    /// @notice The hard cap max supply of the token
    /// @dev If zero, the token has no mint cap
    uint256  public immutable maxSupply;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _maxSupply,
        address _v2Router,
        address _protocolWallet,
        uint8 _protocolFee,
        uint8 _liquidityFee,
        uint8 _teamFee,
        bool _limitsActive,
        bool _blacklistActive
    )
        ERC20SwapTax(
            _name,
            _symbol,
            _initialSupply,
            _v2Router,
            _protocolWallet,
            _protocolFee,
            _liquidityFee,
            _teamFee,
            _limitsActive,
            _blacklistActive
        )
    {
        maxSupply = _maxSupply;
    }

    /// @notice Mint to the contract owner
    /// @param to The address to receive the mint
    /// @param amount The amount to mint
    /// @dev If there is a maxSupply, check we're still below
    function mintTo(address to, uint256 amount) external onlyOwner {
        if (maxSupply != 0) require(totalSupply + amount < maxSupply, "MAX");
        _mint(to, amount);
    }
}
