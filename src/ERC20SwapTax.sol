// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20Metadata, IERC20} from "./interfaces/IERC20Metadata.sol";
import {Ownable} from "./dependencies/Ownable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";

/// @title ERC20 Swap Tax Token
/// @notice Token with a tax on swaps through the UniswapV2Pair
/// @dev Tax is swapped to ETH and sent to dev wallet
/// @dev This is a basic implementation and there is no wallet restrictions or swap delays
contract ERC20SwapTax is IERC20Metadata, Ownable {
    /// @notice The UniswapV2 Router
    IUniswapV2Router02 public immutable uniswapV2Router;

    /// @notice The UniswapV2 Pair of address(this) / WETH
    address public immutable uniswapV2Pair;

    /// @notice The percent buy tax
    uint256 public immutable buyTax = 5;

    /// @notice The percent sell tax
    uint256 public immutable sellTax = 5;

    /// @notice The wallet to receive ETH from tax swaps
    address payable public teamWallet;

    /// @inheritdoc IERC20Metadata
    uint8 public constant override decimals = 18;

    /// @inheritdoc IERC20Metadata
    string public override name;

    /// @inheritdoc IERC20Metadata
    string public override symbol;

    /// @inheritdoc IERC20
    uint256 public constant override totalSupply = 1_000_000 * 10 ** decimals;

    /// @inheritdoc IERC20
    mapping(address => uint256) public override balanceOf;

    /// @inheritdoc IERC20
    mapping(address => mapping(address => uint256)) public override allowance;

    /// @notice The maximum amount of tax that can be swapped to ETH at one time
    uint256 public maxTaxSwap = 15_000 * 10 ** decimals;

    /// @notice The minimum amount of tax that can be swapped to ETH at one time
    /// @dev The contract will accumulate tax until this amount
    uint256 public minTaxSwap = 15_000 * 10 ** decimals;

    /// @dev Addresses excluded from the tax
    mapping(address => bool) private _isExcludedFromFee;

    /// @notice Are swaps enabled yet
    bool public tradingOpen;

    /// @dev Is the contract currently performing a tax swap
    bool private _inSwap = false;

    /// @dev Are tax swaps enabled
    bool private _swapEnabled = false;

    /// @notice Locks actions during a tax swap
    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    receive() external payable {}

    constructor(string memory name_, string memory symbol_) Ownable(_msgSender()) {
        name = name_;
        symbol = symbol_;

        // set the router. change this value depending on the chain!
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        // handle pair and router approvals
        _approve(address(this), address(uniswapV2Router), totalSupply);
        IERC20Metadata(uniswapV2Pair).approve(address(uniswapV2Router), type(uint256).max);

        // set teamWallet to be the original owner
        teamWallet = payable(_msgSender());

        // set supply
        balanceOf[_msgSender()] = totalSupply;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    /// @inheritdoc IERC20
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            allowance[sender][_msgSender()] - amount
        );
        return true;
    }

    /// @dev Internal approval functionality
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /// @dev Internal transfer functionality that takes a tax
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 taxAmount = 0;

        // don't allow swaps until trading is open
        if (!tradingOpen) {
            require(_isExcludedFromFee[to] || _isExcludedFromFee[from], "Trading not active");
        }

        if (from != owner() && to != owner()) {

            // buy
            if (from == uniswapV2Pair && to != address(uniswapV2Router)) {
                taxAmount = (amount * buyTax) / 100;
            }

            // sell
            if (to == uniswapV2Pair) {
                taxAmount = (amount * sellTax) / 100;
            }

            // check if excluded from the fee
            if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
                taxAmount = 0;
            }

            uint256 contractTokenBalance = balanceOf[address(this)];

            // swap tax on sells
            if (
                !_inSwap && to == uniswapV2Pair && _swapEnabled && contractTokenBalance > minTaxSwap
            ) {
                _swapTokensForEth(_min(amount, _min(contractTokenBalance, maxTaxSwap)));

                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0.05 ether) {
                    transferEth(address(this).balance);
                }
            }
        }

        // transfers before opening trade have no tax
        if (!tradingOpen) {
            taxAmount = 0;
        }

        if (taxAmount > 0) {
            balanceOf[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount - taxAmount;
        emit Transfer(from, to, amount - taxAmount);
    }

    /// @dev get the min of two numbers
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    /// @dev Swaps tax tokens for ETH
    function _swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );
    }

    /// @notice Transfer ETH to the team wallet
    function transferEth(uint256 amount) public {
        (bool success, ) = address(teamWallet).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Initialize trading forever
    /// @dev Liquidity should be added first
    function openTrading() external onlyOwner {
        _swapEnabled = true;
        tradingOpen = true;
    }

    /// @notice Manually perform a tax swap and transfer the ETH
    function manualSwap() external {
        require(_msgSender() == teamWallet, "auth");

        uint256 tokenBalance = balanceOf[address(this)];

        if (tokenBalance > 0) {
            _swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            transferEth(ethBalance);
        }
    }

    /// @notice Update the team wallet address
    function updateTeamWallet(address _teamWallet) external onlyOwner {
        require(_teamWallet != address(0), "address(0)");

        teamWallet = payable(_teamWallet);

        _isExcludedFromFee[teamWallet] = true;
    }
}