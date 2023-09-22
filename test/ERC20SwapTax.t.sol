// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/interfaces/IERC20.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/interfaces/IUniswapV2Factory.sol";

import "../src/ERC20SwapTax.sol";

contract ERC20SwapTaxTest is Test {
    uint256 mainnetFork;

    address constant v2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ERC20SwapTax token;
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
        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL")));

        owner = address(this);

        token = new ERC20SwapTax(
            "Test Tax Token",
            "TEST",
            10_000_000 * 1e18,
            v2Router,
            protocolWallet,
            1,
            1,
            1,
            true,
            true
        );
        router = IUniswapV2Router02(token.v2Router());
        pair = token.v2Pair();
        weth = IERC20(router.WETH());

        token.approve(address(router), type(uint256).max);

        router.addLiquidityETH{value: 3 ether}(address(token), token.balanceOf(owner), 0, 0, owner, block.timestamp);

        deal(user, 10 ether);

        wethToToken.push(address(weth));
        wethToToken.push(address(token));

        tokenToWeth.push(address(token));
        tokenToWeth.push(address(weth));

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            wethToToken,
            owner,
            block.timestamp
        );

        token.transfer(user, token.balanceOf(owner));
    }

    function testSetUp() public {
        uint256 totalSupply = token.totalSupply();
        uint256 userBal = token.balanceOf(user);
        assertEq(totalSupply, initialSupply);
        assertGt(userBal, 0);
    }

    function test_GAS_swapBuy() public {
        token.enableTrading();
        token.deactivateLimits();

        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );
    }

    function test_GAS_swapSell() public {
        token.enableTrading();
        token.deactivateLimits();

        vm.startPrank(user);

        token.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            token.balanceOf(user),
            0,
            tokenToWeth,
            user,
            block.timestamp
        );
    }

    function test_GAS_swapSellWithSwap() public {
        token.enableTrading();
        token.deactivateLimits();

        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 5 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        token.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            token.balanceOf(user),
            0,
            tokenToWeth,
            user,
            block.timestamp
        );
    }

    function testSwapBuy(uint96 amount) public {
        vm.assume(amount > 0 ether);

        uint256 totalSupply = token.totalSupply();

        token.enableTrading();
        token.deactivateLimits();

        deal(user, amount);
        vm.startPrank(user);

        uint256 initToken = token.balanceOf(user);
        uint256 initEth = user.balance;
        uint256 initTokenContractBal = token.balanceOf(address(token));
        uint256 initPairBal = token.balanceOf(pair);

        uint256 expectedOut = router.getAmountOut(amount, weth.balanceOf(pair), token.balanceOf(pair));

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(0, wethToToken, user, block.timestamp);

        uint256 finalToken = token.balanceOf(user);
        uint256 finalEth = user.balance;
        uint256 finalTokenContractBal = token.balanceOf(address(token));
        uint256 finalPairBal = token.balanceOf(pair);

        uint256 actualOut = finalToken - initToken;
        uint256 fee = (expectedOut * BUY_FEE) / 100;

        assertEq(initEth - finalEth, amount);
        assertEq(actualOut, expectedOut - fee);

        // invariant balances
        assertEq(finalTokenContractBal - initTokenContractBal, fee);
        assertEq(finalToken - initToken, (initPairBal - finalPairBal) - fee);

        // invariant supply
        assertEq(token.totalSupply(), totalSupply);
    }

    function testSwapSell(uint96 amount) public {
        uint256 totalSupply = token.totalSupply();

        token.enableTrading();
        token.deactivateLimits();

        uint256 initToken = token.balanceOf(user);
        uint256 initContractBal = token.balanceOf(address(token));
        uint256 initPairBal = token.balanceOf(pair);
        uint256 initEth = user.balance;
        uint256 fee = (amount * BUY_FEE) / 100;
        uint256 inWithFee = amount - fee;

        vm.assume(amount > 0.001 ether && amount < initToken);

        uint256 expectedOut = router.getAmountOut(inWithFee, token.balanceOf(pair), weth.balanceOf(pair));

        vm.startPrank(user);

        token.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, tokenToWeth, user, block.timestamp);

        uint256 finalToken = token.balanceOf(user);
        uint256 finalEth = user.balance;
        uint256 finalContractBal = token.balanceOf(address(token));
        uint256 finalPairBal = token.balanceOf(pair);

        assertEq(finalEth - initEth, expectedOut);
        assertEq(initToken - finalToken, amount);

        // invariant balances
        assertEq(finalContractBal - initContractBal, fee);
        assertEq((initToken - finalToken) - fee, finalPairBal - initPairBal);

        // invariant supply
        assertEq(token.totalSupply(), totalSupply);
    }

    function testSwapSellWithSwap(uint96 amount) public {
        uint256 totalSupply = token.totalSupply();

        token.enableTrading();
        token.deactivateLimits();

        deal(user, 100 ether);
        vm.startPrank(user);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 5 ether}(
            0,
            wethToToken,
            user,
            block.timestamp
        );

        uint256 initToken = token.balanceOf(user);
        uint256 initContractBal = token.balanceOf(address(token));
        uint256 initPoolBal = IERC20(pair).balanceOf(owner);
        uint256 initProtocolEth = token.protocolWallet().balance;
        uint256 initOwnerEth = token.teamWallet().balance;
        uint256 initPairBal = token.balanceOf(pair);

        uint256 toSwap = initContractBal <= token.maxContractSwap() ? initContractBal : token.maxContractSwap();

        uint256 fee = (uint256(amount) * 3) / 100;

        assertGt(toSwap, 0);

        vm.assume(amount > 0.001 ether && amount < initToken);

        token.approve(address(router), type(uint256).max);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, tokenToWeth, user, block.timestamp);

        assertGt(token.protocolWallet().balance, initProtocolEth);
        assertGt(token.teamWallet().balance, initOwnerEth);
        assertGt(IERC20(pair).balanceOf(owner), initPoolBal);

        // invariant balances
        assertEq(token.balanceOf(pair) - initPairBal, amount + toSwap - fee);
        assertEq(initToken - token.balanceOf(user), amount);
        fee > toSwap
            ? assertEq(token.balanceOf(address(token)) - initContractBal, fee - toSwap)
            : assertEq(initContractBal - token.balanceOf(address(token)), toSwap - fee);

        // invariant supply
        assertEq(token.totalSupply(), totalSupply);
    }

    function testLimits() public {
        assert(token.limitsActive());
        assert(!token.tradingEnabled());
        assert(!token.contractSwapEnabled());

        uint256 userBal = token.balanceOf(user);

        uint256 maxWallet = token.maxWallet();
        uint256 maxTx = token.maxTransaction();

        assertGt(userBal, maxWallet);

        // no trading
        vm.expectRevert(bytes("TC"));
        vm.prank(user);
        token.transfer(otherUser, userBal);

        vm.prank(owner);
        token.enableTrading();

        // max wallet
        vm.expectRevert(bytes("MAX_WALLET"));
        vm.prank(user);
        token.transfer(otherUser, userBal);

        uint256 expectedOutBig = router.getAmountOut(10 ether, weth.balanceOf(pair), token.balanceOf(pair));
        uint256 expectedOutSmall = router.getAmountOut(0.001 ether, weth.balanceOf(pair), token.balanceOf(pair));

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
        token.approve(address(router), type(uint256).max);

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
        token.enableTrading();
        token.deactivateLimits();

        uint256 initUserBal = token.balanceOf(user);
        uint256 initOwnerBal = token.balanceOf(owner);

        vm.prank(user);
        token.transfer(owner, 1000); // no BL

        uint256 finalUserBal = token.balanceOf(user);
        uint256 finalOwnerBal = token.balanceOf(owner);

        assertEq(finalOwnerBal - initOwnerBal, 1000);
        assertEq(finalOwnerBal - initOwnerBal, initUserBal - finalUserBal);
    }

    function testBlacklisted() public {
        vm.prank(user);
        token.transfer(owner, 500); // no BL

        token.blacklist(user);

        vm.expectRevert(bytes("BL"));
        token.transfer(user, 100);

        vm.expectRevert(bytes("BL"));
        vm.prank(user);
        token.transfer(owner, 100);

        token.enableTrading();
        token.deactivateLimits();

        vm.expectRevert(bytes("BL"));
        token.transfer(user, 100);

        vm.expectRevert(bytes("BL"));
        vm.prank(user);
        token.transfer(owner, 100);
    }

    function testEnableTrading() public {
        assert(!token.tradingEnabled());
        assert(!token.contractSwapEnabled());

        // no transfer
        vm.expectRevert(bytes("TC"));
        vm.prank(user);
        token.transfer(otherUser, 10);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.enableTrading();

        token.enableTrading();
        token.deactivateLimits();

        assert(token.tradingEnabled());
        assert(token.contractSwapEnabled());

        vm.prank(user);
        token.transfer(otherUser, 10);
    }

    function testUpdateSwapThreshold() public {
        assertEq(token.swapThreshold(), 5000 * 1e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateSwapThreshold(4000 * 1e18);

        vm.expectRevert(bytes("BST"));
        token.updateSwapThreshold(10_000 * 1e18);

        vm.expectRevert(bytes("BST"));
        token.updateSwapThreshold(9 * 1e18);

        token.updateSwapThreshold(4000 * 1e18);
        assertEq(token.swapThreshold(), 4000 * 1e18);
    }

    function testUpdateMaxContractSwap() public {
        assertEq(token.maxContractSwap(), 50_000 * 1e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateMaxContractSwap(40_000 * 1e18);

        vm.expectRevert(bytes("BMS"));
        token.updateMaxContractSwap(50_001 * 1e18);

        vm.expectRevert(bytes("BMS"));
        token.updateMaxContractSwap(99 * 1e18);

        token.updateMaxContractSwap(101 * 1e18);
        assertEq(token.maxContractSwap(), 101 * 1e18);
    }

    function testUpdateMaxTransaction() public {
        assertEq(token.maxTransaction(), 100_000 * 1e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateMaxTransaction(60_000 * 1e18);

        vm.expectRevert(bytes("BMT"));
        token.updateMaxTransaction(49_999 * 1e18);

        token.updateMaxTransaction(50_001 * 1e18);
        assertEq(token.maxTransaction(), 50_001 * 1e18);
    }

    function testUpdateMaxWallet() public {
        assertEq(token.maxWallet(), 100_000 * 1e18);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateMaxWallet(200_000 * 1e18);

        vm.expectRevert(bytes("BMW"));
        token.updateMaxWallet(99_999 * 1e18);

        token.updateMaxWallet(100_001 * 1e18);
        assertEq(token.maxWallet(), 100_001 * 1e18);
    }

    function testUpdateContractSwapEnabled() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateContractSwapEnabled(true);

        assert(!token.contractSwapEnabled());
        token.updateContractSwapEnabled(true);
        assert(token.contractSwapEnabled());
        token.updateContractSwapEnabled(false);
        assert(!token.contractSwapEnabled());
    }

    function testUpdateFees() public {
        assertEq(token.totalSwapFee(), 3);
        assertEq(token.protocolFee(), 1);
        assertEq(token.liquidityFee(), 1);
        assertEq(token.teamFee(), 1);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.updateFees(1, 2, 1);

        vm.expectRevert(bytes("BF"));
        token.updateFees(2, 2, 2);

        token.updateFees(2, 1, 2);

        assertEq(token.totalSwapFee(), 5);
        assertEq(token.protocolFee(), 2);
        assertEq(token.liquidityFee(), 1);
        assertEq(token.teamFee(), 2);
    }

    function testExcludeFromLimits() public {
        assert(!token.isExcludedFromLimits(user));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.excludeFromLimits(user, true);

        token.excludeFromLimits(user, true);
        assert(token.isExcludedFromLimits(user));
    }

    function testExcludeFromFees() public {
        assert(!token.isExcludedFromFees(user));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(user);
        token.excludeFromFees(user, true);

        token.excludeFromFees(user, true);
        assert(token.isExcludedFromFees(user));
    }

    function testUpdateAmm() public {
        assert(token.isAmm(pair));
        assert(!token.isAmm(address(otherUser)));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.updateAmm(otherUser, true);

        vm.expectRevert(bytes("FP"));
        token.updateAmm(pair, false);

        token.updateAmm(otherUser, true);
        assert(token.isAmm(address(otherUser)));
        token.updateAmm(otherUser, false);
        assert(!token.isAmm(address(otherUser)));
    }

    function testUpdateProtocolWallet() public {
        assertEq(token.protocolWallet(), protocolWallet);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.updateProtocolWallet(otherUser);

        token.updateProtocolWallet(otherUser);

        assertEq(token.protocolWallet(), otherUser);
    }

    function testUpdateTeamWallet() public {
        assertEq(token.teamWallet(), owner);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.updateTeamWallet(otherUser);

        token.updateTeamWallet(otherUser);

        assertEq(token.teamWallet(), otherUser);
    }

    function testSweepToken() public {
        vm.prank(user);
        token.transfer(address(token), 1e18);

        uint256 initContractBal = token.balanceOf(address(token));
        uint256 initOwnerBal = token.balanceOf(owner);

        assertGt(initContractBal, 0);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.sweepToken(address(token), otherUser);

        token.sweepToken(address(token), owner);

        uint256 finalContractBal = token.balanceOf(address(token));
        uint256 finalOwnerBal = token.balanceOf(owner);

        uint256 ownerDelta = finalOwnerBal - initOwnerBal;

        assertEq(initContractBal - finalContractBal, ownerDelta);
    }

    function testSweepEth() public {
        payable(token).transfer(1 ether);

        uint256 initContractBal = address(token).balance;
        uint256 initOwnerBal = owner.balance;

        assertGt(initContractBal, 0);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.sweepEth(otherUser);

        token.sweepEth(owner);

        uint256 finalContractBal = address(token).balance;
        uint256 finalOwnerBal = owner.balance;

        uint256 ownerDelta = finalOwnerBal - initOwnerBal;

        assertEq(initContractBal - finalContractBal, ownerDelta);
    }

    function testBlacklist() public {
        assert(!token.isBlacklisted(user));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.blacklist(user);

        vm.expectRevert(bytes("BLU"));
        token.blacklist(pair);

        vm.expectRevert(bytes("BLU"));
        token.blacklist(address(router));

        token.blacklist(user);
        assert(token.isBlacklisted(user));
    }

    function testUnblacklist() public {
        assert(!token.isBlacklisted(user));

        token.blacklist(user);
        assert(token.isBlacklisted(user));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.unblacklist(user);

        token.unblacklist(user);
        assert(!token.isBlacklisted(user));
    }

    function testDeactivateLimits() public {
        assert(token.limitsActive());

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.deactivateLimits();

        token.deactivateLimits();
        assert(!token.limitsActive());
    }

    function testDeactivateBlacklist() public {
        assert(token.blacklistActive());

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(otherUser);
        token.deactivateBlacklist();

        token.deactivateBlacklist();
        assert(!token.blacklistActive());
    }
}
