// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../access/Ownable.sol";
import "../../swap/interfaces/IPool.sol";
import "../../assets/interfaces/IWETH.sol";
import "../interfaces/IMojitoRouter02.sol";
import "../../crossChain/interfaces/IWrapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract O3KCCMojitoAggregator is Ownable {
    using SafeERC20 for IERC20;

    event LOG_AGG_SWAP (
        uint256 amountOut,
        uint256 fee
    );

    address public WETH = 0x4446Fc4eb47f2f6586f9fAAb68B3498F86C07521;
    address public router = 0x8c8067ed3bC19ACcE28C1953bfC18DC85A2127F7;
    address public O3Wrapper = 0x82B0FFE1DC686DA0F8535bF99A8538cD414e2fd5;
    address public feeCollector;

    uint256 public aggregatorFee = 3 * 10 ** 7;
    uint256 public constant FEE_DENOMINATOR = 10 ** 10;
    uint256 private constant MAX_AGGREGATOR_FEE = 5 * 10**8;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'O3Aggregator: EXPIRED');
        _;
    }

    constructor (address _feeCollector) {
        feeCollector = _feeCollector;
    }

    receive() external payable { }

    function setWETH(address _weth) external onlyOwner {
        WETH = _weth;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    function setO3Wrapper(address _wrapper) external onlyOwner {
        O3Wrapper = _wrapper;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function setAggregatorFee(uint _fee) external onlyOwner {
        require(_fee < MAX_AGGREGATOR_FEE, "aggregator fee exceeds maximum");
        aggregatorFee = _fee;
    }

    function rescueFund(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        if (tokenAddress == WETH && address(this).balance > 0) {
            _sendETH(_msgSender(), address(this).balance);
        }
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function swapExactPTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        address poolAddress,
        uint poolAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        uint aggSwapAmountOutMin,
        bool unwrapETH
    ) external virtual ensure(deadline) {
        if (amountIn == 0) {
            amountIn = IERC20(path[0]).allowance(_msgSender(), address(this));
        }

        require(amountIn != 0, 'O3Aggregator: ZERO_AMOUNT_IN');
        IERC20(path[0]).safeTransferFrom(_msgSender(), address(this), amountIn);

        {
            IERC20(path[0]).safeApprove(poolAddress, amountIn);
            address underlyingToken = address(IPool(poolAddress).coins(0));

            uint256 balanceBefore = IERC20(underlyingToken).balanceOf(address(this));
            IPool(poolAddress).swap(1, 0, amountIn, poolAmountOutMin, deadline);
            amountIn = IERC20(underlyingToken).balanceOf(address(this)) - balanceBefore;

            require(address(underlyingToken) == path[1], "O3Aggregator: INVALID_PATH");
        }

        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(
            false, amountIn, aggSwapAmountOutMin, path[1:], deadline
        );
        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        if (unwrapETH) {
            require(path[path.length - 1] == WETH, "O3Aggregator: INVALID_PATH");
            IWETH(WETH).withdraw(amountOut);
            _sendETH(feeCollector, feeAmount);
            _sendETH(to, amountOut - feeAmount);
        } else {
            IERC20(path[path.length-1]).safeTransfer(feeCollector, feeAmount);
            IERC20(path[path.length-1]).safeTransfer(to, amountOut - feeAmount);
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint swapAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(
            true, amountIn, swapAmountOutMin, path, deadline
        );
        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        IERC20(path[path.length-1]).safeTransfer(feeCollector, feeAmount);
        IERC20(path[path.length-1]).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, address[] calldata path,         // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline, // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData        // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        (uint swapperAmountIn, address tokenFrom) = _swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(
            amountIn, swapAmountOutMin, path, deadline
        );

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: msg.value}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, address[] calldata path, uint deadline
    ) internal returns (uint256, address) {
        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(
            true, amountIn, swapAmountOutMin, path, deadline
        );

        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        IERC20(path[path.length-1]).safeTransfer(feeCollector, feeAmount);
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut - feeAmount, path[path.length-1]);
    }

    function _swapExactTokensForTokensSupportingFeeOnTransferTokens(
        bool pull, uint amountIn, uint amountOutMin, address[] calldata path, uint deadline
    ) internal virtual returns (uint) {
        if (pull) {
            IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        }

        IERC20(path[0]).safeApprove(router, amountIn);
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(address(this));
        IMojitoRouter02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOutMin, path, address(this), deadline
        );
        uint amountOut = IERC20(path[path.length - 1]).balanceOf(address(this)) - balanceBefore;
        return amountOut;
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint swapAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) {
        uint amountOut = _swapExactETHForTokensSupportingFeeOnTransferTokens(
            swapAmountOutMin, path, 0, deadline
        );

        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        IERC20(path[path.length-1]).safeTransfer(feeCollector, feeAmount);
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(
        uint swapAmountOutMin, address[] calldata path, uint fee,              // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline, // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData        // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        (uint swapperAmountIn, address tokenFrom) = _swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(
            swapAmountOutMin, path, fee, deadline
        );

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: fee}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(
        uint swapAmountOutMin, address[] calldata path, uint fee, uint deadline
    ) internal returns (uint, address) {
        uint amountOut = _swapExactETHForTokensSupportingFeeOnTransferTokens(
            swapAmountOutMin, path, fee, deadline
        );

        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        IERC20(path[path.length-1]).safeTransfer(feeCollector, feeAmount);
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut - feeAmount, path[path.length-1]);
    }

    function _swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint swapAmountOutMin, address[] calldata path, uint fee, uint deadline
    ) internal virtual returns (uint) {
        uint balanceBefore = IERC20(path[path.length-1]).balanceOf(address(this));
        IMojitoRouter02(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value - fee}(
            swapAmountOutMin, path, address(this), deadline
        );
        uint amountOut = IERC20(path[path.length-1]).balanceOf(address(this)) - balanceBefore;
        return amountOut;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint swapAmountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        require(path[path.length-1] == WETH, "O3Aggregator: INVALID_PATH");

        IERC20(path[0]).safeTransferFrom(_msgSender(), address(this), amountIn);
        IERC20(path[0]).safeApprove(router, amountIn);

        uint balanceBefore = address(this).balance;
        IMojitoRouter02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn, swapAmountOutMin, path, address(this), deadline
        );

        uint amountOut = address(this).balance - balanceBefore;
        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        _sendETH(feeCollector, feeAmount);
        _sendETH(to, amountOut - feeAmount);
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}(new bytes(0));
        require(success, 'O3Aggregator: ETH_TRANSFER_FAILED');
    }
}
