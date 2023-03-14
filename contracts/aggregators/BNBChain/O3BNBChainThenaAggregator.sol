// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../access/Ownable.sol";
import "./interfaces/IBNBChainThenaRouter.sol";
import "../../swap/interfaces/IPool.sol";
import "./interfaces/IBNBChainThenaPair.sol";
import "./interfaces/IBNBChainThenaFactory.sol";
import "../../assets/interfaces/IWETH.sol";
import "../../crossChain/interfaces/IWrapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract O3BNBChainThenaAggregator is Ownable {
    using SafeERC20 for IERC20;

    event LOG_AGG_SWAP (
        uint256 amountOut,
        uint256 fee
    );

    address public WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public factory = 0xAFD89d21BdB66d00817d4153E055830B1c2B3970;
    address public O3Wrapper = 0xCCB7a45E36f22eDE66b6222A0A55c547E6D516D7;
    address public feeCollector;

    uint256 public aggregatorFee = 3 * 10 ** 7;
    uint256 public aggregatorFeeStable = 2 * 10 ** 6;

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

    function setFactory(address _factory) external onlyOwner {
        factory = _factory;
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

    function setAggregatorFeeStable(uint _fee) external onlyOwner {
        require(_fee < MAX_AGGREGATOR_FEE, "stable swap aggregator fee exceeds maximum");
        aggregatorFeeStable = _fee;
    }

    function getAggFeeRate(IBNBChainThenaRouter.route[] calldata routes) internal view returns (uint) {
        if (routes[routes.length-1].stable) {
            return aggregatorFeeStable;
        }

        return aggregatorFee;
    }

    function rescueFund(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        if (tokenAddress == WETH && address(this).balance > 0) {
            (bool success,) = _msgSender().call{value: address(this).balance}(new bytes(0));
            require(success, 'ETH_TRANSFER_FAILED');
        }
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'O3Aggregator: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'O3Aggregator: ZERO_ADDRESS');
    }

    function pairFor(address tokenA, address tokenB, bool stable) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1, stable)),
            hex'8d3d214c094a9889564f695c3e9fa516dd3b50bc3258207acd7f8b8e6b94fb65' // init code hash
        )))));
    }

    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) public view returns (uint amount, bool stable) {
        address pair = pairFor(tokenIn, tokenOut, true);
        uint amountStable;
        uint amountVolatile;
        if (IBNBChainThenaFactory(factory).isPair(pair)) {
            amountStable = IBNBChainThenaPair(pair).getAmountOut(amountIn, tokenIn);
        }
        pair = pairFor(tokenIn, tokenOut, false);
        if (IBNBChainThenaFactory(factory).isPair(pair)) {
            amountVolatile = IBNBChainThenaPair(pair).getAmountOut(amountIn, tokenIn);
        }
        return amountStable > amountVolatile ? (amountStable, true) : (amountVolatile, false);
    }

    function swapExactPTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn, address poolAddress, uint poolAmountOutMin, address ptoken,
        IBNBChainThenaRouter.route[] calldata routes,
        address to, uint deadline, uint aggSwapAmountOutMin, bool unwrapETH
    ) external virtual ensure(deadline) {
        if (amountIn == 0) {
            amountIn = IERC20(ptoken).allowance(_msgSender(), address(this));
        }

        require(amountIn != 0, 'O3Aggregator: ZERO_AMOUNT_IN');
        IERC20(ptoken).safeTransferFrom(_msgSender(), address(this), amountIn);

        {
            IERC20(ptoken).safeApprove(poolAddress, amountIn);
            require(address(IPool(poolAddress).coins(0)) == routes[0].from, "O3Aggregator: INVALID_PATH");

            uint256 balanceBefore = IERC20(routes[0].from).balanceOf(address(this));
            IPool(poolAddress).swap(1, 0, amountIn, poolAmountOutMin, deadline);
            amountIn = IERC20(routes[0].from).balanceOf(address(this)) - balanceBefore;
        }

        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(false, amountIn, aggSwapAmountOutMin, routes);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

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

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn, uint swapAmountOutMin,
        IBNBChainThenaRouter.route[] calldata routes,
        address to, uint deadline
    ) external virtual ensure(deadline) {
        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(true, amountIn, swapAmountOutMin, routes);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        IERC20(toToken).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, IBNBChainThenaRouter.route[] calldata routes, // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline,            // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData                     // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        (uint swapperAmountIn, address tokenFrom) = _swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(amountIn, swapAmountOutMin, routes);

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: msg.value}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactTokensForTokensSupportingFeeOnTransferTokensCrossChain(
        uint amountIn, uint swapAmountOutMin, IBNBChainThenaRouter.route[] calldata routes
    ) internal returns (uint256, address) {
        uint amountOut = _swapExactTokensForTokensSupportingFeeOnTransferTokens(true, amountIn, swapAmountOutMin, routes);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut - feeAmount, toToken);
    }

    function _swapExactTokensForTokensSupportingFeeOnTransferTokens(
        bool pull, uint amountIn, uint amountOutMin, IBNBChainThenaRouter.route[] calldata routes
    ) internal virtual returns (uint) {
        if (pull) {
            IERC20(routes[0].from).safeTransferFrom(
                msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn
            );
        } else {
            IERC20(routes[0].from).safeTransfer(pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn);
        }

        address toToken = routes[routes.length-1].to;
        uint balanceBefore = IERC20(toToken).balanceOf(address(this));
        _swapSupportingFeeOnTransferTokens(routes, address(this));
        uint amountOut = IERC20(toToken).balanceOf(address(this)) - balanceBefore;
        require(amountOut >= amountOutMin, 'O3Aggregator: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint swapAmountOutMin,
        IBNBChainThenaRouter.route[] calldata routes,
        address to, uint deadline
    ) external virtual payable ensure(deadline) {
        uint amountOut = _swapExactETHForTokensSupportingFeeOnTransferTokens(swapAmountOutMin, routes, 0);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        IERC20(toToken).safeTransfer(to, amountOut - feeAmount);
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(
        uint swapAmountOutMin, IBNBChainThenaRouter.route[] calldata routes, uint fee, // args for dex
        address poolAddress, address tokenTo, uint256 minDy, uint256 deadline,       // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData               // args for wrapper
    ) external virtual payable ensure(deadline) returns (bool) {
        (uint swapperAmountIn, address tokenFrom) = _swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(swapAmountOutMin, routes, fee);

        IERC20(tokenFrom).safeApprove(O3Wrapper, swapperAmountIn);

        return IWrapper(O3Wrapper).swapAndBridgeOut{value: fee}(
            poolAddress, tokenFrom, tokenTo, swapperAmountIn, minDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _swapExactETHForTokensSupportingFeeOnTransferTokensCrossChain(
        uint swapAmountOutMin, IBNBChainThenaRouter.route[] calldata routes, uint fee
    ) internal returns (uint, address) {
        uint amountOut = _swapExactETHForTokensSupportingFeeOnTransferTokens(swapAmountOutMin, routes, fee);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;

        address toToken = routes[routes.length-1].to;
        IERC20(toToken).safeTransfer(feeCollector, feeAmount);
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut - feeAmount, toToken);
    }

    function _swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint swapAmountOutMin,
        IBNBChainThenaRouter.route[] calldata routes,
        uint fee
    ) internal virtual returns (uint) {
        require(routes[0].from == WETH, 'O3Aggregator: INVALID_PATH');
        uint amountIn = msg.value - fee;
        require(amountIn > 0, 'O3Aggregator: INSUFFICIENT_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn));

        address toToken = routes[routes.length-1].to;
        uint balanceBefore = IERC20(toToken).balanceOf(address(this));
        _swapSupportingFeeOnTransferTokens(routes, address(this));
        uint amountOut = IERC20(toToken).balanceOf(address(this)) - balanceBefore;
        require(amountOut >= swapAmountOutMin, 'O3Aggregator: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, uint swapAmountOutMin,
        IBNBChainThenaRouter.route[] calldata routes,
        address to, uint deadline
    ) external virtual ensure(deadline) {
        uint amountOut = _swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, swapAmountOutMin, routes);
        uint feeAmount = amountOut * getAggFeeRate(routes) / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        IWETH(WETH).withdraw(amountOut);

        _sendETH(feeCollector, feeAmount);
        _sendETH(to, amountOut - feeAmount);
    }

    function _swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn, uint swapAmountOutMin,
        IBNBChainThenaRouter.route[] calldata routes
    ) internal virtual returns (uint) {
        require(routes[routes.length - 1].to == WETH, 'O3Aggregator: INVALID_PATH');
        IERC20(routes[0].from).safeTransferFrom(
            msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn
        );
        uint balanceBefore = IERC20(WETH).balanceOf(address(this));
        _swapSupportingFeeOnTransferTokens(routes, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this)) - balanceBefore;
        require(amountOut >= swapAmountOutMin, 'O3Aggregator: INSUFFICIENT_OUTPUT_AMOUNT');
        return amountOut;
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}(new bytes(0));
        require(success, 'O3Aggregator: ETH_TRANSFER_FAILED');
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(IBNBChainThenaRouter.route[] calldata routes, address _to) internal virtual {
        for (uint i; i < routes.length; i++) {
        	(address input, address output) = (routes[i].from, routes[i].to);
            (address token0,) = sortTokens(input, output);
            IBNBChainThenaPair pair = IBNBChainThenaPair(pairFor(routes[i].from, routes[i].to, routes[i].stable));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput,) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
            (amountOutput,) = getAmountOut(amountInput, input, output);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < routes.length - 1 ? pairFor(routes[i+1].from, routes[i+1].to, routes[i+1].stable) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
}
