// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../access/Ownable.sol";
import "../../swap/interfaces/IPool.sol";
import "../../assets/interfaces/IWETH.sol";
import "../interfaces/IVelodromeRouter.sol";
import "../../crossChain/interfaces/IWrapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract O3OptimismVelodromeAggregator is Ownable {
    using SafeERC20 for IERC20;

    event LOG_AGG_SWAP (
        uint256 amountOut,
        uint256 fee
    );

    address public WETH = 0x4200000000000000000000000000000000000006;
    address public router = 0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9;
    address public O3Wrapper = 0x5ae7ff97F40DF101edABa31D5f89b70f600d9820;
    address public feeCollector;

    uint256 public aggregatorFee = 2 * 10 ** 6;
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

    function swapExactPTokensForTokens(
        uint256 amountIn, address callproxy,
        address poolAddress, uint poolAmountOutMin, address ptoken,
        IVelodromeRouter.route[] calldata routes,
        address to, uint deadline, uint aggSwapAmountOutMin, bool unwrapETH
    ) external virtual ensure(deadline) {
        {
            address caller = _msgSender();

            if (callproxy != address(0) && amountIn == 0) {
                amountIn = IERC20(ptoken).allowance(callproxy, address(this));
                caller = callproxy;
            }

            require(amountIn != 0, "O3Aggregator: amountIn cannot be zero");
            IERC20(ptoken).safeTransferFrom(caller, address(this), amountIn);
        }

        IERC20(ptoken).safeApprove(poolAddress, amountIn);
        amountIn = IPool(poolAddress).swap(1, 0, amountIn, poolAmountOutMin, deadline);
        (uint amountOut, uint feeAmount) = _swapExactTokensForTokens(
            amountIn, aggSwapAmountOutMin, routes, deadline
        );

        address toToken = routes[routes.length-1].to;
        if (unwrapETH) {
            require(toToken == WETH, "O3Aggregator: INVALID_PATH");
            IWETH(WETH).withdraw(amountOut);
            _sendETH(feeCollector, feeAmount);
            _sendETH(to, amountOut - feeAmount);
        } else {
            IERC20(toToken).safeTransfer(feeCollector, feeAmount);
            IERC20(toToken).safeTransfer(to, amountOut - feeAmount);
        }
    }

    function swapExactTokensForTokens(
        uint amountIn, uint swapAmountOutMin,
        IVelodromeRouter.route[] calldata routes,
        address to, uint deadline
    ) external virtual ensure(deadline) {
        IERC20(routes[0].from).safeTransferFrom(_msgSender(), address(this), amountIn);

        (uint amountOut, uint feeAmount) = _swapExactTokensForTokens(
            amountIn, swapAmountOutMin, routes, deadline
        );

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        IERC20(toToken).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactTokensForTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, IVelodromeRouter.route[] calldata routes, // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline,          // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData                 // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        IERC20(routes[0].from).safeTransferFrom(_msgSender(), address(this), amountIn);
        (uint swapperAmountIn, address tokenFrom) = _swapExactTokensForTokensCrossChain(
            amountIn, swapAmountOutMin, routes, deadline
        );

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: msg.value}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactTokensForTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, IVelodromeRouter.route[] calldata routes, uint deadline
    ) internal returns (uint256, address) {
        (uint amountOut, uint feeAmount) = _swapExactTokensForTokens(
            amountIn, swapAmountOutMin, routes, deadline
        );

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        return (amountOut - feeAmount, toToken);
    }

    function _swapExactTokensForTokens(
        uint amountIn, uint amountOutMin, IVelodromeRouter.route[] calldata routes, uint deadline
    ) internal virtual returns (uint, uint) {
        IERC20(routes[0].from).safeApprove(router, amountIn);
        uint[] memory amounts = IVelodromeRouter(router).swapExactTokensForTokens(
            amountIn, amountOutMin, routes, address(this), deadline
        );

        uint amountOut = amounts[amounts.length-1];
        uint feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;

        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut, feeAmount);
    }

    function swapExactETHForTokens(
        uint swapAmountOutMin,
        IVelodromeRouter.route[] calldata routes,
        address to, uint deadline
    ) external virtual payable ensure(deadline) {
        (uint amountOut, uint feeAmount) = _swapExactETHForTokens(
            swapAmountOutMin, routes, 0, deadline
        );

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        IERC20(toToken).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactETHForTokensCrossChain(
        uint swapAmountOutMin, IVelodromeRouter.route[] calldata routes, uint fee, // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline,     // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData            // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        (uint swapperAmountIn, address tokenFrom) = _swapExactETHForTokensCrossChain(
            swapAmountOutMin, routes, fee, deadline
        );

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: fee}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactETHForTokensCrossChain(
        uint swapAmountOutMin, IVelodromeRouter.route[] calldata routes, uint fee, uint deadline
    ) internal returns (uint, address) {
        (uint amountOut, uint feeAmount) = _swapExactETHForTokens(
            swapAmountOutMin, routes, fee, deadline
        );

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);

        return (amountOut - feeAmount, toToken);
    }

    function _swapExactETHForTokens(
        uint amountOutMin,
        IVelodromeRouter.route[] calldata routes,
        uint fee, uint deadline
    ) internal virtual returns (uint, uint) {
        uint amountIn = msg.value - fee;
        require(amountIn > 0, 'O3Aggregator: INSUFFICIENT_INPUT_AMOUNT');
        require(routes[0].from == WETH, "O3Aggregator: INVALID_PATH");

        IWETH(WETH).deposit{value: amountIn}();
        return _swapExactTokensForTokens(amountIn, amountOutMin, routes, deadline);
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint swapAmountOutMin,
        IVelodromeRouter.route[] calldata routes,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        require(routes[routes.length-1].to == WETH, "O3Aggregator: INVALID_PATH");

        IERC20(routes[0].from).safeTransferFrom(_msgSender(), address(this), amountIn);

        (uint amountOut, uint feeAmount) = _swapExactTokensForTokens(
            amountIn, swapAmountOutMin, routes, deadline
        );

        IWETH(WETH).withdraw(amountOut);

        _sendETH(feeCollector, feeAmount);
        _sendETH(to, amountOut - feeAmount);
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}(new bytes(0));
        require(success, 'O3Aggregator: ETH_TRANSFER_FAILED');
    }
}
