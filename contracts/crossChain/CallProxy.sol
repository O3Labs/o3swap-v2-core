pragma solidity ^0.8.0;

import "./Interface.sol";
import "./Utils.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CallProxy is ICallProxy {
    using SafeERC20 for IERC20;

    function proxyCall(
        address ptoken,
        address receiver,
        uint256 amount,
        bytes memory callee,
        bytes memory callData
    ) public override returns(bool) {
        IERC20 token = IERC20(ptoken);
        address toContract = Utils.bytesToAddress(callee);
        token.approve(toContract, amount);
        toContract.call(callData);
        token.safeTransfer(receiver, token.balanceOf(address(this)));
        return true;
    }
}
