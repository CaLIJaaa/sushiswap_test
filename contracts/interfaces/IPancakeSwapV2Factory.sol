// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPancakeSwapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
