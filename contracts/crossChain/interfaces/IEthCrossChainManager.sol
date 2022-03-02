// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEthCrossChainManager {
    function crossChain(
        uint64 _toChainId,
        bytes calldata _toContract,
        bytes calldata _method,
        bytes calldata _txData
    ) external returns (bool);
}
