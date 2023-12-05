// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/UniswapV2Factory.sol";
import "../src/UniswapV2Pair.sol";
import "@solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract UniswapV2Test is Test {
    UniswapV2Factory factory;
    MockERC20 token0;
    MockERC20 token1;
    UniswapV2Pair pair;

    address bob;

    function setUp() public {
        bob = makeAddr("bob");

        // Deploy the factory
        factory = new UniswapV2Factory();

        // Deploy mock ERC20 tokens
        token0 = new MockERC20("Token 0", "TKNA", 18);
        token1 = new MockERC20("Token 1", "TKNB", 18);

        // Mint some tokens to this contract for testing
        token0.mint(address(this), 1e18);
        token1.mint(address(this), 1e18);

        // Create a pair
        address pairAddress = factory.createPair(
            address(token0),
            address(token1)
        );
        pair = UniswapV2Pair(pairAddress);
    }

    function testPairCreation() public {
        assertEq(factory.allPairsLength(), 1, "Pair creation failed");
    }

    function testMint() public {
        // Transfer tokens to the pair contract
        uint256 initialAmount0 = 1e18;
        uint256 initialAmount1 = 1e18;
        token0.transfer(address(pair), initialAmount0);
        token1.transfer(address(pair), initialAmount1);

        // Approve the pair to spend tokens
        token0.approve(address(pair), initialAmount0);
        token1.approve(address(pair), initialAmount1);

        // Call the mint function
        pair.mint(address(this));

        // Check if liquidity tokens were minted
        assertGt(pair.balanceOf(address(this)), 0, "Minting failed");
    }

    function testBurn() public {
        // First mint some liquidity tokens
        testMint();

        // Transfer liquidity tokens to the pair contract
        uint256 liquidity = pair.balanceOf(address(this));
        pair.transfer(address(pair), liquidity);

        // Approve and burn liquidity tokens
        pair.approve(address(pair), liquidity);
        (uint amount0, uint amount1) = pair.burn(address(this));

        // Check if liquidity tokens were burned and tokens were received
        assertEq(pair.balanceOf(address(this)), 0, "Burning failed");
        assertGt(token0.balanceOf(address(this)), 0, "Did not receive Token A");
        assertGt(token1.balanceOf(address(this)), 0, "Did not receive Token B");
    }

    function testSwap() public {
        uint256 amount0In = 1e16; // Amount of token0 to swap
        uint256 amount1Out = 1e16; // Expected amount of token1 to receive
        uint256 minAmount0Out = 0; // Minimum acceptable amount of token0 (set to 0 if not swapping token0)
        uint256 minAmount1Out = 0; // Minimum acceptable amount of token1 (set to 0 if not swapping token1)

        testMint();

        vm.startPrank(bob);
        token0.mint(bob, 1e18);

        // Assume bob has enough token0 and has approved the pair contract
        uint256 userToken0BalanceBefore = token0.balanceOf(bob);
        uint256 userToken1BalanceBefore = token1.balanceOf(bob);
        uint256 pairToken0BalanceBefore = token0.balanceOf(address(pair));
        uint256 pairToken1BalanceBefore = token1.balanceOf(address(pair));

        // Bob approves the pair contract to spend their token0
        token0.approve(address(pair), amount0In);

        // Perform the swap
        pair.swap(
            0,
            amount1Out,
            bob,
            amount0In,
            0,
            minAmount0Out,
            minAmount1Out
        );

        // Check balances after the swap
        uint256 userToken0BalanceAfter = token0.balanceOf(bob);
        uint256 userToken1BalanceAfter = token1.balanceOf(bob);
        uint256 pairToken0BalanceAfter = token0.balanceOf(address(pair));
        uint256 pairToken1BalanceAfter = token1.balanceOf(address(pair));

        // Asserts
        assertGt(
            token1.balanceOf(bob),
            userToken1BalanceBefore,
            "Swap did not increase bob's token1 balance"
        );
        assertLt(
            token0.balanceOf(bob),
            userToken0BalanceBefore,
            "Swap did not decrease bob's token0 balance"
        );
        assertGt(
            token0.balanceOf(address(pair)),
            pairToken0BalanceBefore,
            "Swap did not increase pair's token0 balance"
        );
        assertLt(
            token1.balanceOf(address(pair)),
            pairToken1BalanceBefore,
            "Swap did not decrease pair's token1 balance"
        );
    }
}
