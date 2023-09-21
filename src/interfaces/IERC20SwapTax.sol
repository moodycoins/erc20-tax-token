// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//
// === fees ===
// Generally, taxes on tokens are used for either
//   1) paying the team
//   2) revenue share
//   3) adding to liquidity
// So i decided to give deployers these three options. Project also occasionally
// burn tokens from taxes, but I didn't feel that was essential functionality.
//
// === limits and blacklists ===
// Due to the nature of the token's reliance on the v2Router and its own liquidity,
// it's natural that contract owners might want more granular control over
// actions that could potentially harm the LP. The contract gives owners the option
// to activate:
//   - limits on maxTransaction sizes and maxWallet sizes
//   - blacklist that restricts swaps and transfers
//

/// @title ERC20 Swap Tax Interface
/// @notice An ERC20 Swap Tax token takes a fee from all token swaps
interface IERC20SwapTax {
    // immutables
    function v2Router() external view returns (address);
    function v2Pair() external view returns (address);
    function initialSupply() external view returns (uint256);

    // fees
    function totalSwapFee() external view returns (uint8);
    function protocolFee() external view returns (uint8);
    function liquidityFee() external view returns (uint8);
    function teamFee() external view returns (uint8);

    function teamWallet() external view returns (address);
    function protocolWallet() external view returns (address);

    // params
    function swapThreshold() external view returns (uint128);
    function maxContractSwap() external view returns (uint128);
    function maxTransaction() external view returns (uint128);
    function maxWallet() external view returns (uint128);

    // state
    function limitsActive() external view returns (bool);
    function blacklistActive() external view returns (bool);
    function tradingEnabled() external view returns (bool);
    function contractSwapEnabled() external view returns (bool);

    // addresses
    function isAmm(address) external view returns (bool);
    function isBlacklisted(address) external view returns (bool);
    function isExcludedFromFees(address) external view returns (bool);
    function isExcludedFromLimits(address) external view returns (bool);

    // events
    event AmmUpdated(address indexed account, bool isAmm);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event TeamWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event ProtocolWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event SwapAndAdd(uint256 tokensSwapped, uint256 ethToLp, uint256 tokenToLp);
}
