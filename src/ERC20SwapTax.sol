// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "./libraries/Math.sol";
import {ERC20} from "./dependencies/ERC20.sol";
import {Ownable} from "./dependencies/Ownable.sol";
import {IERC20SwapTax} from "./interfaces/IERC20SwapTax.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

/// @title ERC20 Swap Tax
/// @author MoodyCoins
/// @notice A gas-optimized ERC20 token with taxable V2 swaps
/// @dev Blacklist and wallet limits are enabled in the constructor
/// @dev Rewards can be allocated to three locations:
///   1. The teamWallet
///   2. The protocolWallet
///   3. Back into the LP
/// You can choose the distribution to each in the constructor
contract ERC20SwapTax is ERC20, IERC20SwapTax, Ownable {
    using Math for uint256;

    uint8 public immutable MAX_TAX = 5;
    uint256 public immutable override initialSupply;

    address public immutable override v2Router;
    address public immutable override v2Pair;

    address public override protocolWallet;
    address public override teamWallet;

    bool public override tradingEnabled;
    bool public override contractSwapEnabled;

    bool public override limitsActive;
    bool public override blacklistActive;

    uint8 public override totalSwapFee;
    uint8 public override protocolFee;
    uint8 public override liquidityFee;
    uint8 public override teamFee;

    mapping(address => bool) public override isAmm;
    mapping(address => bool) public override isBlacklisted;
    mapping(address => bool) public override isExcludedFromFees;
    mapping(address => bool) public override isExcludedFromLimits;

    uint128 public override swapThreshold;
    uint128 public override maxContractSwap;
    uint128 public override maxTransaction;
    uint128 public override maxWallet;

    bool private _swapping;
    address internal immutable WETH;
    address internal constant DEAD = address(0xdEaD);

    receive() external payable {}

    /// @dev Constructor
    /// @param _name The token name
    /// @param _symbol The token symbol
    /// @param _initialSupply The initial token supply
    /// @param _v2Router The address of the main uniswap style V2 router
    /// @param _protocolWallet The wallet to receive the protocolFee
    /// @param _protocolFee The fee allocated to the protocol
    /// @param _liquidityFee The fee re-allocated into the LP
    /// @param _teamFee The fee re-allocated into the LP
    /// @param _limitsActive Are limits on transaction and wallets sizes active
    /// @param _blacklistActive Is the blacklist active
    /// @dev The sum of all the fees must be < MAX_FEE = 5
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _v2Router,
        address _protocolWallet,
        uint8 _protocolFee,
        uint8 _liquidityFee,
        uint8 _teamFee,
        bool _limitsActive,
        bool _blacklistActive
    ) ERC20(_name, _symbol, 18) {
        initialSupply = _initialSupply;

        protocolWallet = _protocolWallet;
        teamWallet = owner();

        limitsActive = _limitsActive;
        blacklistActive = _blacklistActive;

        updateFees(_protocolFee, _liquidityFee, _teamFee);

        v2Router = _v2Router;
        WETH = IUniswapV2Router02(v2Router).WETH();
        v2Pair = IUniswapV2Factory(IUniswapV2Router02(v2Router).factory()).createPair(address(this), WETH);

        // Note: reasonable values have been chosen, edit them freely, but be wary of
        // setting maxContractSwap or swapThreshold too high, as that can result in
        // large contract sales
        swapThreshold   = uint128(initialSupply.mulDiv(5  , 10_000));
        maxContractSwap = uint128(initialSupply.mulDiv(50 , 10_000));
        maxTransaction  = uint128(initialSupply.mulDiv(100, 10_000));
        maxWallet       = uint128(initialSupply.mulDiv(100, 10_000));

        updateAmm(v2Pair, true);

        excludeFromLimits(address(this), true);
        excludeFromLimits(owner(), true);
        excludeFromLimits(v2Router, true);
        excludeFromLimits(v2Pair, true);
        excludeFromLimits(DEAD, true);

        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        excludeFromFees(DEAD, true);

        // approve router
        allowance[address(this)][v2Router] = type(uint256).max;
        emit Approval(address(this), v2Router, type(uint256).max);

        // only ever called once
        _mint(owner(), initialSupply);
    }

    /// @dev A gas-optimized internal _transfer function with a tax
    /// @dev If the tokens in this contract are over the threshold, they will be swapped
    /// @dev A fee is taken on buys and sells to an AMM
    function _transfer(address from, address to, uint256 amount) internal override {
        if (blacklistActive) require(!(isBlacklisted[from] || isBlacklisted[to]), "BL");
        if (limitsActive) _checkLimits(from, to, amount);

        bool excluded = isExcludedFromFees[from] || isExcludedFromFees[to];
        uint8 _swapFee = totalSwapFee;

        if (excluded || _swapFee == 0 || amount == 0) {
            // no fees or excluded -> process transfer normally
            super._transfer(from, to, amount);
            return;
        }

        // if currently swapping exclude from all fees
        excluded = _swapping;

        bool isBuy = isAmm[from];

        if (isBuy || excluded || !contractSwapEnabled || balanceOf[address(this)] < swapThreshold) {
            // ...
        } else {
            _swapping = true;
            _swapBack();
            _swapping = false;
        }

        // keep the sum of balances invariant:
        //
        // balance[from] -= amount;
        // balanceOf[this] += fee;
        // balanceOf[to] += amount - fee;

        balanceOf[from] -= amount;
        uint256 fee = 0;

        if ((isBuy || isAmm[to]) && !excluded) {
            fee = amount.mulDiv(_swapFee, 100);
            unchecked { balanceOf[address(this)] += fee; } // prettier-ignore
            emit Transfer(from, address(this), fee);
        }

        unchecked { balanceOf[to] += (amount - fee); } // prettier-ignore
        emit Transfer(from, to, amount - fee);
    }

    /// @dev Check various conditions if limits are in effect
    function _checkLimits(address from, address to, uint256 amount) internal view {
        if (from == owner() || to == owner() || to == DEAD || _swapping) return;

        if (!tradingEnabled) {
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

    /// @dev Swap contract balance to ETH if over the threshold
    function _swapBack() private {
        uint256 balance = balanceOf[address(this)];

        if (balance == 0) return;
        if (balance > maxContractSwap) balance = maxContractSwap;

        uint256 protocolTokens = balance.mulDiv(protocolFee, totalSwapFee);
        uint256 teamTokens = balance.mulDiv(teamFee, totalSwapFee);

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

        IUniswapV2Router02(v2Router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Add v2 liquidity
    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        IUniswapV2Router02(v2Router).addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    /// @dev Once trading is active, can never be inactive
    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        contractSwapEnabled = true;
    }

    /// @dev Update the threshold for contract swaps
    function updateSwapThreshold(uint128 newThreshold) external onlyOwner {
        require(newThreshold >= totalSupply.mulDiv(1, 1_000_000), "BST"); // >= 0.0001%
        require(newThreshold <= totalSupply.mulDiv(5, 10_000), "BST"); // <= 0.05%
        swapThreshold = newThreshold;
    }

    /// @dev Update the max contract swap
    function updateMaxContractSwap(uint128 newMaxSwap) external onlyOwner {
        require(newMaxSwap >=  totalSupply.mulDiv(1, 100_000), "BMS"); // >= 0.001%
        require(newMaxSwap <= totalSupply.mulDiv(50, 10_000), "BMS"); // <= 0.5%
        maxContractSwap = newMaxSwap;
    }

    /// @dev Update the max transaction while limits are in effect
    function updateMaxTransaction(uint128 newMaxTx) external onlyOwner {
        require(newMaxTx >= totalSupply.mulDiv(50, 10_000), "BMT"); // >= 0.5%
        maxTransaction = newMaxTx;
    }

    /// @dev Update the max wallet while limits are in effect
    function updateMaxWallet(uint128 newMaxWallet) external onlyOwner {
        require(newMaxWallet >= totalSupply.mulDiv(100, 10_000), "BMW"); // >= 1%
        maxWallet = newMaxWallet;
    }

    /// @dev Emergency disabling of contract sales
    function updateContractSwapEnabled(bool enabled) external onlyOwner {
        contractSwapEnabled = enabled;
    }

    /// @dev Update the swap fees
    function updateFees(uint8 _protocolFee, uint8 _liquidityFee, uint8 _teamFee) public onlyOwner {
        require(_protocolFee + _liquidityFee + _teamFee <= MAX_TAX, "BF");
        totalSwapFee = _protocolFee + _liquidityFee + _teamFee;
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
    function updateAmm(address account, bool amm) public onlyOwner {
        if (!amm) require(account != v2Pair, "FP");
        isAmm[account] = amm;
        emit AmmUpdated(account, amm);
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
        require(account != address(v2Pair), "BLU");
        require(account != address(v2Router), "BLU");
        isBlacklisted[account] = true;
    }

    /// @dev Remove an account from the blacklist
    /// @dev Callable even after blacklist has been renounced
    function unblacklist(address account) public onlyOwner {
        isBlacklisted[account] = false;
    }

    /// @dev Irreversible action, limits can never be reinstated
    function deactivateLimits() external onlyOwner {
        limitsActive = false;
    }

    /// @dev Renounce blacklist authority
    function deactivateBlacklist() public onlyOwner {
        blacklistActive = false;
    }
}
