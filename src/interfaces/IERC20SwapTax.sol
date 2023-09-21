// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Some comments on the contract:
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
// it seems natural that contract owners might want more granular control over
// actions that could potentially harm the LP. The contract gives owners the option
// to activate:
//   - Limits on maxTransaction sizes and maxWallet sizes
//   - Blacklist list that restricts swaps and transfers
//
// Why would you need limits? If your token launched with very low liquidity and
// market cap, an early buyer could buy and sell a significant portion of the supply,
// which would fill the contract balance with lots of taxes to be sold, which would
// put significant sell pressure on your token.

interface IERC20SwapTax {
    // immutables
    function v2Router() external view returns (address);
    function v2Pair() external view returns (address);
    function initialSupply() external view returns (uint256);

    // params
    function teamWallet() external view returns (address);
    function protocolWallet() external view returns (address);
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

    // fees
    function totalSwapFee() external view returns (uint8);
    function protocolFee() external view returns (uint8);
    function liquidityFee() external view returns (uint8);
    function teamFee() external view returns (uint8);

    // events
    event AmmUpdated(address indexed account, bool isAmm);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event TeamWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event ProtocolWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event SwapAndAdd(uint256 tokensSwapped, uint256 ethToLp, uint256 tokenToLp);
}
