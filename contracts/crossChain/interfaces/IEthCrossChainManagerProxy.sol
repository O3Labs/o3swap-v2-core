// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IEthCrossChainManagerProxy {
    function getEthCrossChainManager() external view returns (address);
}
