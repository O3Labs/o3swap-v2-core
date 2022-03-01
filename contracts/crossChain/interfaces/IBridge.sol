// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBridge {
    function bridgeOut(
        address fromAssetHash,
        uint64 toChainId,
        bytes memory toAddress,
        uint256 amount,
        bytes memory callData
    ) external returns(bool);
}
