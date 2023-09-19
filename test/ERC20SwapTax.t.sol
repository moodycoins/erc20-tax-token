// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/interfaces/IERC20.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/interfaces/IUniswapV2Factory.sol";

import "../src/ERC20SwapTax.sol";

contract ERC20SwapTaxTest is Test {
    uint256 mainnetFork;

    ERC20SwapTax taxToken;
    IUniswapV2Router02 router;
    address pair;
    IERC20 weth;

    address owner;
    address user = address(0xBEEF);
    address otherUser = address(0xBEE);
    address protocolWallet = address(0xFEE);

    uint256 constant BUY_FEE = 3;
    uint256 constant SELL_FEE = 3;

    address[] wethToToken;
    address[] tokenToWeth;

    uint256 constant initialSupply = 10_000_000 * 1e18;

    receive() external payable {}

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        owner = address(this);

        taxToken = new ERC20SwapTax("TEST", "TEST", 1, 1, 1, address(protocolWallet), true, true);
        router = IUniswapV2Router02(taxToken.uniswapV2Router());
        pair = taxToken.uniswapV2Pair();
        weth = IERC20(router.WETH());

        taxToken.approve(address(router), type(uint256).max);

        router.addLiquidityETH{value: 3 ether}(
            address(taxToken),
            taxToken.balanceOf(owner),
            0,
            0,
            owner,
            block.timestamp
        );

        deal(user, 10 ether);

        wethToToken.push(address(weth));
        wethToToken.push(address(taxToken));

        tokenToWeth.push(address(taxToken));
        tokenToWeth.push(address(weth));

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            wethToToken,
            owner,
            block.timestamp
        );

        taxToken.transfer(user, taxToken.balanceOf(owner));
    }

    function testSetUp() public {
        uint256 totalSupply = taxToken.totalSupply();
        uint256 userBal = taxToken.balanceOf(user);
        assertEq(totalSupply, initialSupply);
        assertGt(userBal, 0);
    }

    function test_GAS_swapBuy() public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );
    }

    function test_GAS_swapSell() public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        vm.startPrank(user);

        taxToken.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            taxToken.balanceOf(user),
            0,
            tokenToWeth,
            user,
            block.timestamp
        );
    }

    function test_GAS_swapSellWithSwap() public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 5 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        taxToken.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            taxToken.balanceOf(user),
            0,
            tokenToWeth,
            user,
            block.timestamp
        );
    }

    function testSwapBuy(uint96 amount) public {
        vm.assume(amount > 0 ether);

        taxToken.enableTrading();
        taxToken.removeLimits();

        deal(user, amount);
        vm.startPrank(user);

        uint256 initToken = taxToken.balanceOf(user);
        uint256 initEth = user.balance;
        uint256 initTokenContractBal = taxToken.balanceOf(address(taxToken));

        uint256 expectedOut = router.getAmountOut(amount, weth.balanceOf(pair), taxToken.balanceOf(pair));

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(0, wethToToken, user, block.timestamp);

        uint256 finalToken = taxToken.balanceOf(user);
        uint256 finalEth = user.balance;
        uint256 finalTokenContractBal = taxToken.balanceOf(address(taxToken));

        uint256 actualOut = finalToken - initToken;
        uint256 fee = (expectedOut * BUY_FEE) / 100;

        assertEq(initEth - finalEth, amount);
        assertEq(actualOut, expectedOut - fee);

        assertEq(finalTokenContractBal - initTokenContractBal, fee);
    }

    function testSwapSell(uint96 amount) public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        uint256 initToken = taxToken.balanceOf(user);
        uint256 initContractBal = taxToken.balanceOf(address(taxToken));
        uint256 initEth = user.balance;
        uint256 fee = (amount * BUY_FEE) / 100;
        uint256 inWithFee = amount - fee;

        vm.assume(amount > 0.001 ether && amount < initToken);

        uint256 expectedOut = router.getAmountOut(inWithFee, taxToken.balanceOf(pair), weth.balanceOf(pair));

        vm.startPrank(user);

        taxToken.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, tokenToWeth, user, block.timestamp);

        uint256 finalToken = taxToken.balanceOf(user);
        uint256 finalEth = user.balance;
        uint256 finalContractBal = taxToken.balanceOf(address(taxToken));

        assertEq(finalEth - initEth, expectedOut);
        assertEq(initToken - finalToken, amount);
        assertEq(finalContractBal - initContractBal, fee);
    }

    function testSwapSellWithSwap(uint96 amount) public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        deal(user, 100 ether);
        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 5 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        uint256 initToken = taxToken.balanceOf(user);

        uint256 initContractBal = taxToken.balanceOf(address(taxToken));
        uint256 initPoolBal = IERC20(pair).balanceOf(owner);
        uint256 initProtocolEth = taxToken.protocolWallet().balance;
        uint256 initOwnerEth = taxToken.teamWallet().balance;

        uint256 toSwap = initContractBal <= taxToken.maxSwap() ? initContractBal : taxToken.maxSwap();

        uint256 fee = (uint256(amount) * 3) / 100;

        assertGt(toSwap, 0);

        vm.assume(amount > 0.001 ether && amount < initToken);

        taxToken.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, tokenToWeth, user, block.timestamp);

        uint256 finalContractBal = taxToken.balanceOf(address(taxToken));
        uint256 finalPoolBal = IERC20(pair).balanceOf(owner);
        uint256 finalProtocolEth = taxToken.protocolWallet().balance;
        uint256 finalOwnerEth = taxToken.teamWallet().balance;

        assertGt(finalPoolBal, initPoolBal);
        assertGt(finalProtocolEth, initProtocolEth);
        assertGt(finalOwnerEth, initOwnerEth);

        assertEq(finalContractBal + toSwap, initContractBal + fee);
    }

    function testLimits() public {
        assert(taxToken.limitsActive());
        assert(!taxToken.tradingActive());
        assert(!taxToken.swapEnabled());

        uint256 userBal = taxToken.balanceOf(user);

        uint256 maxWallet = taxToken.maxWallet();
        uint256 maxTx = taxToken.maxTransaction();

        assertGt(userBal, maxWallet);

        // no trading
        vm.expectRevert(bytes("TC"));
        vm.prank(user);
        taxToken.transfer(otherUser, userBal);

        vm.prank(owner);
        taxToken.enableTrading();

        // max wallet
        vm.expectRevert(bytes("MAX_WALLET"));
        vm.prank(user);
        taxToken.transfer(otherUser, userBal);

        uint256 expectedOutBig = router.getAmountOut(10 ether, weth.balanceOf(pair), taxToken.balanceOf(pair));
        uint256 expectedOutSmall = router.getAmountOut(0.001 ether, weth.balanceOf(pair), taxToken.balanceOf(pair));

        assertGt(expectedOutBig, maxTx);
        assertLt(expectedOutSmall, maxTx);

        deal(user, 10 ether);

        // expect the router error
        // fails because MAX_TX
        vm.expectRevert(bytes("UniswapV2: TRANSFER_FAILED"));
        vm.prank(user);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 10 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        // fails because MAX_WALLET - buy
        vm.expectRevert(bytes("UniswapV2: TRANSFER_FAILED"));
        vm.prank(user);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 0.001 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        vm.prank(user);
        taxToken.approve(address(router), type(uint256).max);

        // fails because MAX_TX - sell
        vm.expectRevert(bytes("TransferHelper: TRANSFER_FROM_FAILED"));
        vm.prank(user);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(userBal, 0, tokenToWeth, user, block.timestamp);

        deal(otherUser, 10 ether);

        // good
        vm.prank(otherUser);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 0.001 ether}(
            0,
            wethToToken,
            otherUser,
            block.timestamp
        );
    }

    function testTransferNoSwap() public {
        taxToken.enableTrading();
        taxToken.removeLimits();

        uint256 initUserBal = taxToken.balanceOf(user);
        uint256 initOwnerBal = taxToken.balanceOf(owner);

        vm.prank(user);
        taxToken.transfer(owner, 1000); // no BL

        uint256 finalUserBal = taxToken.balanceOf(user);
        uint256 finalOwnerBal = taxToken.balanceOf(owner);

        assertEq(finalOwnerBal - initOwnerBal, 1000);
        assertEq(finalOwnerBal - initOwnerBal, initUserBal - finalUserBal);
    }

    function testBlacklist() public {
        vm.prank(user);
        taxToken.transfer(owner, 500); // no BL

        taxToken.blacklist(user);

        vm.expectRevert(bytes("BL"));
        taxToken.transfer(user, 100);

        vm.expectRevert(bytes("BL"));
        vm.prank(user);
        taxToken.transfer(owner, 100);

        taxToken.enableTrading();
        taxToken.removeLimits();

        vm.expectRevert(bytes("BL"));
        taxToken.transfer(user, 100);

        vm.expectRevert(bytes("BL"));
        vm.prank(user);
        taxToken.transfer(owner, 100);
    }
}
