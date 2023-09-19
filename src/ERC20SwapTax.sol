// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "./libraries/Math.sol";
import {ERC20} from "./dependencies/ERC20.sol";
import {Ownable} from "./dependencies/Ownable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

/// @title ERC20 Swap Tax
/// @author MoodyCoins
/// @notice A gas-optimized ERC20 token with taxable V2 swaps
/// @dev Blacklist and wallet limits are enabled in the constructor
/// @dev Rewards can be allocated to three locations:
///   1. To the teamWallet
///   2. To the protocolWallet
///   3. Back into the LP
/// You can choose the distribution to each in the constructor
contract ERC20SwapTax is ERC20, Ownable {
    using Math for uint256;

    uint256 constant MAX_SUPPLY = 10_000_000 * 1e18;
    uint256 constant MAX_TAX = 5;

    address constant DEAD = address(0xdEaD);
    address immutable WETH;

    address public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    address public protocolWallet;
    address public teamWallet;

    uint256 public maxTransaction;
    uint256 public maxWallet;

    bool private _swapping;

    bool public limitsActive = false;
    bool public blacklistActive = false;

    bool public swapEnabled = false;
    bool public tradingActive = false;

    uint8 public swapFee;

    uint8 public protocolFee;
    uint8 public liquidityFee;
    uint8 public teamFee;

    uint128 public swapThreshold;
    uint128 public maxSwap;

    mapping(address => bool) public isAmm;
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedFromLimits;

    event AmmPairUpdated(address indexed pair, bool value);
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event TeamWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event ProtocolWalletUpdated(address indexed newWallet, address indexed oldWallet);
    event SwapAndAdd(uint256 tokensSwapped, uint256 ethLiquidity, uint256 tokenLiquidity);

    receive() external payable {}

    /// @dev Constructor
    /// @param _name The token name
    /// @param _symbol The token symbol
    /// @param _protocolFee The fee allocated back to the protocol
    /// @param _liquidityFee The fee re-allocated into the LP
    /// @param _teamFee The fee allocated to the team
    /// @param _protocolWallet The wallet to receive protocol fee portion
    /// @param _hasLimits Are there transaction and wallet limits in place
    /// @param _hasBlacklist Is there a blacklist for this token
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _protocolFee,
        uint8 _liquidityFee,
        uint8 _teamFee,
        address _protocolWallet,
        bool _hasLimits,
        bool _hasBlacklist
    ) ERC20(_name, _symbol, 18) {
        protocolWallet = _protocolWallet;
        teamWallet = owner();

        if (_hasLimits) limitsActive = true;
        if (_hasBlacklist) blacklistActive = true;

        updateFees(_protocolFee, _liquidityFee, _teamFee);

        IUniswapV2Router02 router = IUniswapV2Router02(
            // Uniswap V2 router address on Mainnet
            // Must update this if necessary
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        WETH = router.WETH();
        uniswapV2Router = address(router);
        uniswapV2Pair = IUniswapV2Factory(router.factory()).createPair(address(this), WETH);

        setAmm(uniswapV2Pair, true);

        excludeFromLimits(uniswapV2Pair, true);
        excludeFromLimits(uniswapV2Router, true);

        maxTransaction = MAX_SUPPLY.mulDiv(1, 100); // 1%
        maxWallet = MAX_SUPPLY.mulDiv(1, 100); // 1%
        swapThreshold = uint128(MAX_SUPPLY.mulDiv(5, 10_000)); // 0.05%
        maxSwap = uint128(MAX_SUPPLY.mulDiv(50, 10_000)); // 0.50%

        excludeFromFees(DEAD, true);
        excludeFromLimits(DEAD, true);

        excludeFromFees(owner(), true);
        excludeFromLimits(owner(), true);

        excludeFromFees(address(this), true);
        excludeFromLimits(address(this), true);

        // approve router
        allowance[address(this)][uniswapV2Router] = type(uint256).max;
        emit Approval(address(this), uniswapV2Router, type(uint256).max);

        // only ever called once
        _mint(msg.sender, MAX_SUPPLY); // 60%
    }

    /// @dev Once trading is active, can never be inactive
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
    }

    /// @dev Irreversible action, limits can never be reinstated
    function removeLimits() external onlyOwner {
        limitsActive = false;
    }

    /// @dev Update the threshold for contract swaps
    function updateSwapThreshold(uint128 newThreshold) external onlyOwner {
        require(newThreshold >= (totalSupply * 1) / 1_000_000, "BSA"); // >= 0.0001%
        require(newThreshold <= (totalSupply * 5) / 10_000, "BSA"); // <= 0.05%
        swapThreshold = newThreshold;
    }

    /// @dev Update the max contract swap
    function updateMaxSwap(uint128 newMaxSwap) external onlyOwner {
        require(newMaxSwap >= (totalSupply * 1) / 100_000, "BSA"); // >= 0.001%
        require(newMaxSwap <= (totalSupply * 5) / 1000, "BSA"); // <= 0.5%
        maxSwap = newMaxSwap;
    }

    /// @dev Update the max transaction while limits are in effect
    function updateMaxTxnAmount(uint256 newAmount) external onlyOwner {
        require(newAmount >= ((totalSupply * 5) / 1000), "BMT"); // >= 0.5%
        maxTransaction = newAmount;
    }

    /// @dev Update the max wallet while limits are in effect
    function updateMaxWalletAmount(uint256 newAmount) external onlyOwner {
        require(newAmount >= ((totalSupply * 1) / 100), "BMW"); // >= 1%
        maxWallet = newAmount;
    }

    /// @dev Emergency disabling of contract sales
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    /// @dev Update the swap fees
    function updateFees(uint8 _protocolFee, uint8 _liquidityFee, uint8 _teamFee) public onlyOwner {
        require((swapFee = _protocolFee + _liquidityFee + _teamFee) <= MAX_TAX, "BF");
        protocolFee = _protocolFee;
        liquidityFee = _liquidityFee;
        teamFee = _teamFee;
    }

    /// @dev Exclude account from the limited max transaction size
    function excludeFromLimits(address account, bool excluded) public onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    /// @dev Exclude account from all fees
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    /// @dev Designate address as an AMM pair to process fees
    function setAmm(address account, bool amm) public onlyOwner {
        if (!amm) require(account != uniswapV2Pair, "FP");
        isAmm[account] = amm;
        emit AmmPairUpdated(account, amm);
    }

    /// @dev Update the protocol wallet
    function updateProtocolWallet(address newWallet) external onlyOwner {
        emit ProtocolWalletUpdated(newWallet, protocolWallet);
        protocolWallet = newWallet;
    }

    /// @dev Update the team wallet
    function updateTeamWallet(address newWallet) external onlyOwner {
        emit TeamWalletUpdated(newWallet, teamWallet);
        teamWallet = newWallet;
    }

    /// @dev Check various conditions if limits are in effect
    function _checkLimits(address from, address to, uint256 amount) internal view {
        if (from == owner() || to == owner() || to == DEAD || _swapping) return;

        if (!tradingActive) {
            require(isExcludedFromFees[from] || isExcludedFromFees[to], "TC");
        }
        // buy
        if (isAmm[from] && !isExcludedFromLimits[to]) {
            require(amount <= maxTransaction, "MAX_TX");
            require(amount + balanceOf[to] <= maxWallet, "MAX_WALLET");
        }
        // sell
        else if (isAmm[to] && !isExcludedFromLimits[from]) {
            require(amount <= maxTransaction, "MAX_TX");
        }
        // transfer
        else if (!isExcludedFromLimits[to]) {
            require(amount + balanceOf[to] <= maxWallet, "MAX_WALLET");
        }
    }

    /// @dev A gas-optimized internal _transfer tax function
    /// @dev If the tokens in this contract are over the threshold, they will be swapped
    /// @dev A fee is taken on buys and sells to an AMM
    function _transfer(address from, address to, uint256 amount) internal override {
        require(!(isBlacklisted[from] || isBlacklisted[to]), "BL");

        if (limitsActive) _checkLimits(from, to, amount);

        bool excluded = isExcludedFromFees[from] || isExcludedFromFees[to];
        uint8 _swapFee = swapFee;

        if (excluded || _swapFee == 0 || amount == 0) {
            // no fees or excluded -> process transfer normally
            super._transfer(from, to, amount);

            return;
        }

        // if currently swapping exclude from all fees
        excluded = _swapping;

        bool isBuy = isAmm[from];

        if (isBuy || excluded || balanceOf[address(this)] < swapThreshold || !swapEnabled) {
            // do nothing
        } else {
            _swapping = true;
            _swapBack();
            _swapping = false;
        }

        // instead of 4 state modifications we do 3 while
        // keeping the balances invariant:
        //
        // balance[from] -= amount;
        // balanceOf[this] += fee;
        // balanceOf[to] += amount - fee;

        // take whole amount
        balanceOf[from] -= amount;

        uint256 fee = 0;

        if (!(isBuy || isAmm[to]) || excluded) {
            // do nothing
        } else {
            fee = amount.mulDiv(_swapFee, 100);

            unchecked {
                balanceOf[address(this)] += fee;
            }
            emit Transfer(from, address(this), fee);
        }

        unchecked {
            balanceOf[to] += (amount - fee);
        }
        emit Transfer(from, to, amount - fee);
    }

    /// @dev Swap contract balance to ETH if over the threshold
    function _swapBack() private {
        uint256 balance = balanceOf[address(this)];

        if (balance == 0) return;
        if (balance > maxSwap) balance = maxSwap;

        uint256 protocolTokens = balance.mulDiv(protocolFee, swapFee);
        uint256 teamTokens = balance.mulDiv(teamFee, swapFee);

        // half the remaining tokens are for liquidity
        uint256 liquidityTokens = (balance - protocolTokens - teamTokens) / 2;
        uint256 swapTokens = balance - liquidityTokens;

        uint256 ethBalance = address(this).balance;

        _swapTokensForEth(swapTokens);

        ethBalance = address(this).balance - ethBalance;

        uint256 ethForTeam = ethBalance.mulDiv(teamTokens, swapTokens);
        uint256 ethForLiquidity = ethBalance - ethForTeam - ethBalance.mulDiv(protocolTokens, swapTokens);

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            _addLiquidity(liquidityTokens, ethForLiquidity);

            emit SwapAndAdd(swapTokens, ethForLiquidity, liquidityTokens);
        }

        // don't verify the call so transfers out can fail
        (bool success, ) = teamWallet.call{value: ethForTeam}("");
        (success, ) = protocolWallet.call{value: address(this).balance}("");
    }

    /// @dev Perform a v2 swap for ETH
    function _swapTokensForEth(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        IUniswapV2Router02(uniswapV2Router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Add v2 liquidity
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        IUniswapV2Router02(uniswapV2Router).addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    /// @dev Withdraw token stuck in the contract
    function sweepToken(address token, address to) external onlyOwner {
        require(token != address(0), "ZA");
        ERC20(token).transfer(to, ERC20(token).balanceOf(address(this)));
    }

    /// @dev Withdraw eth stuck in the contract
    function sweepEth(address to) external onlyOwner {
        (bool success, ) = to.call{value: address(this).balance}("");
        require(success, "TF");
    }

    /// @dev Blacklist an account
    function blacklist(address account) public onlyOwner {
        require(blacklistActive, "RK");
        require(account != address(uniswapV2Pair) && account != address(uniswapV2Router), "BLU");
        isBlacklisted[account] = true;
    }

    /// @dev Remove an account from the blacklist
    /// @dev Callable even after blacklist has been renounced
    function unblacklist(address account) public onlyOwner {
        isBlacklisted[account] = false;
    }

    /// @dev Renounce blacklist authority
    function renounceBlacklist() public onlyOwner {
        blacklistActive = false;
    }
}
