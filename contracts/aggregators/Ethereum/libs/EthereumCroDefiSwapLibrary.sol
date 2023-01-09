// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.8.0;

import '../../interfaces/IUniswapV2Pair.sol';

interface IEthereumCroDefiSwapFactory {
    function totalFeeBasisPoint() external view returns (uint);
}

library EthereumCroDefiSwapLibrary {
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CroDefiSwapLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CroDefiSwapLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'69d637e77615df9f235f642acebbdad8963ef35c5523142078c9b8f9d0ceba7e' // init code hash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'CroDefiSwapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CroDefiSwapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, address factory) internal view returns (uint amountOut) {
        require(amountIn > 0, 'CroDefiSwapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'CroDefiSwapLibrary: INSUFFICIENT_LIQUIDITY');

        uint magnifier = 10000;
        uint totalFeeBasisPoint = IEthereumCroDefiSwapFactory(factory).totalFeeBasisPoint();

        uint amountInWithFee = amountIn * (magnifier - totalFeeBasisPoint);
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * magnifier + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
