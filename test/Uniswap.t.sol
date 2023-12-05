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
    MockERC20 tokenA;
    MockERC20 tokenB;
    UniswapV2Pair pair;

    address bob;

    function setUp() public {
        bob = makeAddr("bob");

        // Deploy the factory
        factory = new UniswapV2Factory();

        // Deploy mock ERC20 tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint some tokens to this contract for testing
        tokenA.mint(address(this), 1e18);
        tokenB.mint(address(this), 1e18);

        // Create a pair
        address pairAddress = factory.createPair(
            address(tokenA),
            address(tokenB)
        );
        pair = UniswapV2Pair(pairAddress);
    }

    function testPairCreation() public {
        assertEq(factory.allPairsLength(), 1, "Pair creation failed");
    }

    function testMint() public {
        // Transfer tokens to the pair contract
        uint256 initialAmountA = 1e18;
        uint256 initialAmountB = 1e18;
        tokenA.transfer(address(pair), initialAmountA);
        tokenB.transfer(address(pair), initialAmountB);

        // Approve the pair to spend tokens
        tokenA.approve(address(pair), initialAmountA);
        tokenB.approve(address(pair), initialAmountB);

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
        assertGt(tokenA.balanceOf(address(this)), 0, "Did not receive Token A");
        assertGt(tokenB.balanceOf(address(this)), 0, "Did not receive Token B");
    }

    function testSwap() public {
        vm.prank(bob);
        tokenA.mint(bob, 1e18);

        emit log_named_uint("bobA", ERC20(tokenA).balanceOf(bob));
        emit log_named_uint("bobB", ERC20(tokenB).balanceOf(bob));

        // First mint some liquidity tokens
        testMint();

        vm.startPrank(bob);

        uint256 swapAmount = 1e16;
        tokenA.approve(address(pair), swapAmount);

        pair.swap(swapAmount, 100, bob);

        emit log_named_uint("bobA", ERC20(tokenA).balanceOf(bob));
        emit log_named_uint("bobB", ERC20(tokenB).balanceOf(bob));

        // // Check if the swap was successful
        assertGt(tokenB.balanceOf(bob), 0, "Swap failed");
    }
}
