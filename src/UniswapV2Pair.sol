// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@solady/tokens/ERC20.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC3156.sol";

contract UniswapV2Pair is ERC20, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    // Flash loan fee rate (e.g., 0.0009 for 0.09%)
    uint256 public constant FLASH_LOAN_FEE_RATE = 0.0000 ether;

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

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = balance0;
        reserve1 = balance1;
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

        _update(balance0, balance1);

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
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        uint256 amount0In,
        uint256 amount1In,
        uint256 minAmount0Out,
        uint256 minAmount1Out
    ) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        require(amount0In > 0 || amount1In > 0, "Insufficient input amount");
        (uint256 balance0, uint256 balance1) = getReserves();

        // Transfer input tokens to the contract
        if (amount0In > 0) {
            require(
                ERC20(token0).transferFrom(
                    msg.sender,
                    address(this),
                    amount0In
                ),
                "Transfer of token0 failed"
            );
        }
        if (amount1In > 0) {
            require(
                ERC20(token1).transferFrom(
                    msg.sender,
                    address(this),
                    amount1In
                ),
                "Transfer of token1 failed"
            );
        }

        // Calculate new balances after the transfer
        uint256 newBalance0 = ERC20(token0).balanceOf(address(this));
        uint256 newBalance1 = ERC20(token1).balanceOf(address(this));

        // Slippage protection: Ensure the user gets at least the minimum amount specified
        require(
            newBalance0 - reserve0 >= minAmount0Out,
            "Slippage exceeded for token0"
        );
        require(
            newBalance1 - reserve1 >= minAmount1Out,
            "Slippage exceeded for token1"
        );

        // Transfer output tokens to the recipient
        if (amount0Out > 0) ERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) ERC20(token1).transfer(to, amount1Out);

        // Final balance check and reserve update
        newBalance0 = ERC20(token0).balanceOf(address(this));
        newBalance1 = ERC20(token1).balanceOf(address(this));
        // require(
        //     newBalance0 * newBalance1 >= balance0 * balance1,
        //     "K invariant violation"
        // );

        _update(newBalance0, newBalance1);
    }

    // ERC-3156 Flash loan function
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        require(token == token0 || token == token1, "UniswapV2: INVALID_TOKEN");

        uint256 fee = amount.mulWadDown(FLASH_LOAN_FEE_RATE);
        uint256 amountOwed = amount + fee;

        // Ensure the pair has enough liquidity
        uint256 balanceBefore = ERC20(token).balanceOf(address(this));
        require(balanceBefore >= amount, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        // Send the flash loan amount to the receiver
        ERC20(token).transfer(address(receiver), amount);

        // Expect the receiver to return the amount plus fee
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) ==
                keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "UniswapV2: INVALID_RETURN_DATA"
        );

        uint256 balanceAfter = ERC20(token).balanceOf(address(this));
        require(
            balanceAfter >= amountOwed,
            "UniswapV2: INSUFFICIENT_REPAYMENT"
        );

        // Update reserves if necessary
        if (token == token0) {
            _update(balanceAfter, reserve1);
        } else {
            _update(reserve0, balanceAfter);
        }

        return true;
    }

    ////// VIEWS ///////
    function getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    ////// UTILS ///////

    // Internal function to find the minimum of two uint256 values
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
