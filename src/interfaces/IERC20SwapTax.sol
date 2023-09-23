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

    /// @notice The main v2 router address
    function v2Router() external view returns (address);
    /// @notice The main v2 pair address
    function v2Pair() external view returns (address);
    /// @notice The initial token supply
    function initialSupply() external view returns (uint256);

    // fees

    /// @notice The total tax taken on swaps in percent
    function totalSwapFee() external view returns (uint8);
    /// @notice The protocol tax allocation in percent
    function protocolFee() external view returns (uint8);
    /// @notice The liquidity pool tax allocation in percent
    function liquidityFee() external view returns (uint8);
    /// @notice The team tax allocation in percent
    function teamFee() external view returns (uint8);
    /// @notice The address to collect the team fee
    function teamWallet() external view returns (address);
    /// @notice The address to collect the protocol fee
    function protocolWallet() external view returns (address);

    // params

    /// @notice The minimum amount of token that the contract will swap
    function swapThreshold() external view returns (uint128);
    /// @notice The maximum amount of token that the contract will swap
    function maxContractSwap() external view returns (uint128);
    /// @notice If limits are active, the max swap amount
    function maxTransaction() external view returns (uint128);
    /// @notice If limits are active, the max wallet size
    function maxWallet() external view returns (uint128);

    // state

    /// @notice If limits are active
    function limitsActive() external view returns (bool);
    /// @notice If the blacklist is active
    function blacklistActive() external view returns (bool);
    /// @notice If trading through the v2Pair is enabled
    function tradingEnabled() external view returns (bool);
    /// @notice If the contract is allowed to swap
    function contractSwapEnabled() external view returns (bool);

    // addresses

    /// @notice Is the address an automated market-maker pair
    function isAmm(address) external view returns (bool);
    /// @notice Is the address excluded from tax fees
    function isExcludedFromFees(address) external view returns (bool);
    /// @notice Is the address blacklisted
    function isBlacklisted(address) external view returns (bool);
    /// @notice Is the address excluded from limits
    function isExcludedFromLimits(address) external view returns (bool);

    // events
    event AmmUpdated(address indexed account, bool isAmm);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event TeamWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event ProtocolWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event SwapAndAdd(uint256 tokensSwapped, uint256 ethToLp, uint256 tokenToLp);
}
