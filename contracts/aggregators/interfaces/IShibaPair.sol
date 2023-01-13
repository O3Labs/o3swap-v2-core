// SPDX-License-Identifier: AGPL-3.0

pragma solidity >=0.8.0;

import './IUniswapV2Pair.sol';

interface IShibaPair is IUniswapV2Pair {
    function totalFee() external view returns (uint);
}
