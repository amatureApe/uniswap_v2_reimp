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

    function setUp() public {
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
        // Approve the pair to spend tokens
        tokenA.approve(address(pair), 1e18);
        tokenB.approve(address(pair), 1e18);

        // Call the mint function
        pair.mint(address(this));

        // Check if liquidity tokens were minted
        assertGt(pair.balanceOf(address(this)), 0, "Minting failed");
    }

    function testBurn() public {
        // First mint some liquidity tokens
        testMint();

        // Approve and burn liquidity tokens
        pair.approve(address(pair), pair.balanceOf(address(this)));
        pair.burn(address(this));

        // Check if liquidity tokens were burned
        assertEq(pair.balanceOf(address(this)), 0, "Burning failed");
    }

    function testSwap() public {
        // First mint some liquidity tokens
        testMint();

        // Swap tokens
        pair.swap(1e17, 0, address(this));

        // Check if the swap was successful
        assertGt(tokenB.balanceOf(address(this)), 1e18, "Swap failed");
    }
}
