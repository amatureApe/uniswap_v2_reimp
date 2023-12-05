// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@solady/tokens/ERC20.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    address public factory;
    address public token0;
    address public token1;

    uint256 private reserve0;
    uint256 private reserve1;
    uint256 private unlocked = 1;

    // Events
    event Mint(address indexed sender, address indexed to, uint256 amount);
    event Burn(
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );
    event Swap(
        address indexed sender,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    // Constructor
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) ERC20(name, symbol, decimals) {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    function mint(address to) external nonReentrant returns (uint liquidity) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        uint balance0 = ERC20(token0).balanceOf(address(this));
        uint balance1 = ERC20(token1).balanceOf(address(this));
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;

        if (totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1);
        } else {
            liquidity = min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        reserve0 = balance0;
        reserve1 = balance1;

        emit Mint(msg.sender, to, liquidity);
    }

    function burn(
        address to
    ) external nonReentrant returns (uint amount0, uint amount1) {
        uint balance0 = ERC20(token0).balanceOf(address(this));
        uint balance1 = ERC20(token1).balanceOf(address(this));
        uint liquidity = ERC20(address(this)).balanceOf(address(this));

        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;

        require(
            amount0 > 0 && amount1 > 0,
            "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
        );
        _burn(address(this), liquidity);
        ERC20(address(token0)).transfer(to, amount0);
        ERC20(address(token1)).transfer(to, amount1);

        reserve0 = ERC20(token0).balanceOf(address(this));
        reserve1 = ERC20(token1).balanceOf(address(this));

        emit Burn(msg.sender, to, amount0, amount1);
    }

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to
    ) external nonReentrant {
        require(
            amount0Out > 0 || amount1Out > 0,
            "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        require(
            amount0Out < reserve0 && amount1Out < reserve1,
            "UniswapV2: INSUFFICIENT_LIQUIDITY"
        );

        // Transfer the tokens
        if (amount0Out > 0) ERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) ERC20(token1).transfer(to, amount1Out);

        // Update reserves to the current balance if transfers are successful
        uint balance0 = ERC20(token0).balanceOf(address(this));
        uint balance1 = ERC20(token1).balanceOf(address(this));

        // Calculate the inputs based on new balances
        uint amount0In = balance0 > reserve0 - amount0Out
            ? balance0 - (reserve0 - amount0Out)
            : 0;
        uint amount1In = balance1 > reserve1 - amount1Out
            ? balance1 - (reserve1 - amount1Out)
            : 0;
        // require(
        //     amount0In > 0 || amount1In > 0,
        //     "UniswapV2: INSUFFICIENT_INPUT_AMOUNT"
        // );

        // Update the reserves
        reserve0 = balance0;
        reserve1 = balance1;

        // Ensure K is maintained
        require(reserve0 * reserve1 >= amount0In * amount1In, "UniswapV2: K");

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    ////// UTILS ///////

    // Internal function to find the minimum of two uint256 values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
