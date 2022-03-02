// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICallProxy {
    function proxyCall(
        address ptoken,
        address receiver,
        uint256 amount,
        bytes memory callData
    ) external returns(bool);
}
