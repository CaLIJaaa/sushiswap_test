// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IPancakeSwapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakeSwapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IPancakeSwapV2Router {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract PancakeSwapBuyer {

    address private constant PANCAKE_FACTORY = 0x1097053Fd2ea711dad45caCcc45EfF7548fCB362;
    address private constant PANCAKE_ROUTER = 0xEfF92A263d31888d860bD50809A8D171709b7b1c;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    error InsufficientETH();
    error TransferFailed();
    error PairNotFound();
    error InsufficientLiquidity();
    error InvalidToken();
    error InvalidAmount();
    error ApprovalFailed();
    error DeadlineExpired();

    event TokensPurchased(address indexed token, uint256 amountOut, uint256 ethSpent);
    event LiquidityAdded(address indexed token, uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapETHForExactTokens(address token, uint amountOut) public payable {
        if (token == address(0) || token == WETH) revert InvalidToken();
        if (amountOut == 0) revert InvalidAmount();

        address pair = IPancakeSwapV2Factory(PANCAKE_FACTORY).getPair(WETH, token);
        if (pair == address(0)) revert PairNotFound();

        (uint112 reserve0, uint112 reserve1,) = IPancakeSwapV2Pair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        
        address token0 = IPancakeSwapV2Pair(pair).token0();
        bool isWETHToken0 = token0 == WETH;
        
        uint256 amountIn = _getAmountIn(
            amountOut,
            isWETHToken0 ? reserve0 : reserve1,
            isWETHToken0 ? reserve1 : reserve0
        );
        
        if (msg.value < amountIn) revert InsufficientETH();
        
        IWETH(WETH).deposit{value: amountIn}();
        
        if (!IWETH(WETH).transfer(pair, amountIn)) revert TransferFailed();
        
        if (isWETHToken0) {
            IPancakeSwapV2Pair(pair).swap(0, amountOut, msg.sender, "");
        } else {
            IPancakeSwapV2Pair(pair).swap(amountOut, 0, msg.sender, "");
        }
        
        uint256 refund = msg.value - amountIn;
        if (refund > 0) {
            (bool refunded,) = msg.sender.call{value: refund}("");
            if (!refunded) revert TransferFailed();
        }
        
        emit TokensPurchased(token, amountOut, amountIn);
    }
    
    function swapAndAddLiquidity(
        address token,
        uint256 amountOut,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 timeout
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        if (msg.value == 0) revert InsufficientETH();
        
        // calculate amountIn
        uint256 ethForSwap = getAmountETHIn(token, amountOut);
        if (msg.value <= ethForSwap) revert InsufficientETH();
        
        // swap ETH for tokens
        _swapETHForExactTokensToContract(token, amountOut, ethForSwap);
        
        // approve tokens for router
        if (!IERC20(token).approve(PANCAKE_ROUTER, amountOut)) {
            revert ApprovalFailed();
        }
        
        // add liquidity with remaining ETH
        uint256 ethForLiquidity = msg.value - ethForSwap;
        (amountToken, amountETH, liquidity) = IPancakeSwapV2Router(PANCAKE_ROUTER)
            .addLiquidityETH{value: ethForLiquidity}(
                token,
                amountOut,
                amountTokenMin,
                amountETHMin,
                msg.sender,
                block.timestamp + timeout
            );
        
        // return unused tokens and ETH
        uint256 unusedTokens = amountOut - amountToken;
        if (unusedTokens > 0) {
            if (!IERC20(token).transfer(msg.sender, unusedTokens)) {
                revert TransferFailed();
            }
        }
        
        uint256 unusedETH = ethForLiquidity - amountETH;
        if (unusedETH > 0) {
            (bool refunded,) = msg.sender.call{value: unusedETH}("");
            if (!refunded) revert TransferFailed();
        }
        
        emit TokensPurchased(token, amountOut, ethForSwap);
        emit LiquidityAdded(token, amountToken, amountETH, liquidity);
    }
    
    function _swapETHForExactTokensToContract(address token, uint amountOut, uint ethAmount) internal {
        address pair = IPancakeSwapV2Factory(PANCAKE_FACTORY).getPair(WETH, token);
        if (pair == address(0)) revert PairNotFound();

        (uint112 reserve0, uint112 reserve1,) = IPancakeSwapV2Pair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        
        address token0 = IPancakeSwapV2Pair(pair).token0();
        bool isWETHToken0 = token0 == WETH;
        
        IWETH(WETH).deposit{value: ethAmount}();
        if (!IWETH(WETH).transfer(pair, ethAmount)) revert TransferFailed();
        
        if (isWETHToken0) {
            IPancakeSwapV2Pair(pair).swap(0, amountOut, address(this), "");
        } else {
            IPancakeSwapV2Pair(pair).swap(amountOut, 0, address(this), "");
        }
    }
    
    function getAmountETHIn(address token, uint amountOut) public view returns (uint amountIn) {
        if (token == address(0) || token == WETH) revert InvalidToken();
        
        address pair = IPancakeSwapV2Factory(PANCAKE_FACTORY).getPair(WETH, token);
        if (pair == address(0)) revert PairNotFound();
        
        (uint112 reserve0, uint112 reserve1,) = IPancakeSwapV2Pair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) revert InsufficientLiquidity();
        
        address token0 = IPancakeSwapV2Pair(pair).token0();
        bool isWETHToken0 = token0 == WETH;
        
        return _getAmountIn(
            amountOut,
            isWETHToken0 ? reserve0 : reserve1,
            isWETHToken0 ? reserve1 : reserve0
        );
    }
    
    function _getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) private pure returns (uint amountIn) {
        if (amountOut == 0) revert InvalidAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
    
    receive() external payable {}
}