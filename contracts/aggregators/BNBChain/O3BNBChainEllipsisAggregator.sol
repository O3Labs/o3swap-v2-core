// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../../access/Ownable.sol";
import "../../swap/interfaces/IPool.sol";
import "../../assets/interfaces/IWETH.sol";
import "../../crossChain/interfaces/IWrapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IBNBChainEllipsis {
    function coins(uint256 index) external returns (address);
}

 contract O3BNBChainEllipsisAggregator is Ownable {
    using SafeERC20 for IERC20;

    event LOG_AGG_SWAP (
        uint256 amountOut,
        uint256 fee
    );

    address public WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public O3Wrapper = 0xCCB7a45E36f22eDE66b6222A0A55c547E6D516D7;
    address public feeCollector;

    uint256 public aggregatorFee = 4 * 10**6;
    uint256 public constant FEE_DENOMINATOR = 10 ** 10;
    uint256 private constant MAX_AGGREGATOR_FEE = 5 * 10**8;

    modifier ensure(uint256 deadline) {
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

    function setO3Wrapper(address _wrapper) external onlyOwner {
        O3Wrapper = _wrapper;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
    }

    function setAggregatorFee(uint256 _fee) external onlyOwner {
        require(_fee < MAX_AGGREGATOR_FEE, "aggregator fee exceeds maximum");
        aggregatorFee = _fee;
    }

    function rescueFund(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        if (tokenAddress == WETH && address(this).balance > 0) {
            (bool success,) = _msgSender().call{value: address(this).balance}(new bytes(0));
            require(success, 'ETH_TRANSFER_FAILED');
        }
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function exchangePTokensForTokens(
        uint256 amountIn, address ptokenAddr, address ptokenPoolAddr, uint256 ptokenPoolMinDy,
        address ellipsisPoolAddr, address[] calldata path, uint256 ellipsisPoolMinDy,
        address toAddress, uint256 deadline, bool unwrapETH
    ) external virtual ensure(deadline) {
        uint256 amountOut = _exchangePTokensForTokens(
            amountIn, deadline, ptokenAddr, ptokenPoolAddr, ptokenPoolMinDy,
            ellipsisPoolAddr, path, ellipsisPoolMinDy
        );

        uint256 feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        if (unwrapETH) {
            require(path[1] == WETH, "O3Aggregator: INVALID_TO_TOKEN");
            IWETH(WETH).withdraw(amountOut);
            _sendETH(feeCollector, feeAmount);
            _sendETH(toAddress, amountOut - feeAmount);
        } else {
            IERC20(path[1]).safeTransfer(feeCollector, feeAmount);
            IERC20(path[1]).safeTransfer(toAddress, amountOut - feeAmount);
        }
    }

    function _exchangePTokensForTokens(
        uint256 amountIn, uint256 deadline,
        address ptokenAddr, address ptokenPoolAddr, uint256 ptokenPoolMinDy,
        address ellipsisPoolAddr, address[] calldata path, uint256 ellipsisPoolMinDy
    ) internal returns (uint256) {
        if (amountIn == 0) {
            amountIn = IERC20(ptokenAddr).allowance(_msgSender(), address(this));
        }

        IERC20(ptokenAddr).safeTransferFrom(_msgSender(), address(this), amountIn);

        (address underlyingToken, uint256 ellipsisAmountIn) = _ptokenSwap(
            amountIn, ptokenAddr, ptokenPoolAddr, ptokenPoolMinDy, deadline
        );

        require(underlyingToken == path[0], "O3Aggregator: INVALID_PATH");
        return _ellipsisSwap(ellipsisPoolAddr, ellipsisAmountIn, path, ellipsisPoolMinDy);
    }

    function _ptokenSwap(
        uint256 amountIn,
        address ptokenAddr,
        address ptokenPoolAddr,
        uint256 minDy,
        uint256 deadline
    ) internal returns (address, uint256) {
        require(amountIn != 0, "O3Aggregator: amountIn cannot be zero");

        address underlyingToken = address(IPool(ptokenPoolAddr).coins(0));
        uint256 balanceBefore = IERC20(underlyingToken).balanceOf(address(this));
        IERC20(ptokenAddr).safeApprove(ptokenPoolAddr, amountIn);
        IPool(ptokenPoolAddr).swap(1, 0, amountIn, minDy, deadline);

        return (underlyingToken, IERC20(underlyingToken).balanceOf(address(this)) - balanceBefore);
    }

    function _ellipsisSwap(
        address ellipsisPoolAddr,
        uint256 amountIn,
        address[] calldata path,
        uint256 minDy
    ) internal returns (uint256) {
        require(amountIn != 0, "O3Aggregator: amountIn cannot be zero");
        require(path.length == 2, "O3Aggregator: INVALID_PATH");

        IERC20(path[0]).safeApprove(ellipsisPoolAddr, amountIn);
        (int128 i, int128 j) = _getPoolTokenIndex(ellipsisPoolAddr, path[0], path[1]);

        address toToken = IBNBChainEllipsis(ellipsisPoolAddr).coins(uint256(int256(j)));
        uint256 balanceBefore = IERC20(toToken).balanceOf(address(this));
        (bool success,) = ellipsisPoolAddr.call(
            abi.encodeWithSignature("exchange(int128,int128,uint256,uint256)",
            i, j, amountIn, minDy)
        );
        require(success, "O3Aggregator: failed to call 'exchange'");

        return IERC20(toToken).balanceOf(address(this)) - balanceBefore;
    }

    function exchangeTokensForTokens(
        uint256 amountIn,
        address ellipsisPoolAddr,
        uint256 ellipsisPoolMinDy,
        address[] calldata path,
        address toAddress,
        uint256 deadline
    ) external virtual ensure(deadline) {
        IERC20(path[0]).safeTransferFrom(_msgSender(), address(this), amountIn);

        (uint256 amountOut, uint256 feeAmount) = _exchangeTokensForTokens(
            amountIn, ellipsisPoolAddr, ellipsisPoolMinDy, path
        );

        IERC20(path[1]).safeTransfer(feeCollector, feeAmount);
        IERC20(path[1]).safeTransfer(toAddress, amountOut - feeAmount);
    }

    function _exchangeTokensForTokens(
        uint256 amountIn,
        address ellipsisPoolAddr,
        uint256 ellipsisPoolMinDy,
        address[] calldata path
    ) internal returns (uint256, uint256) {
        uint256 amountOut = _ellipsisSwap(ellipsisPoolAddr, amountIn, path, ellipsisPoolMinDy);
        uint256 feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        return (amountOut, feeAmount);
    }

    function exchangeTokensForTokensCrossChain(
        uint256 amountIn, address ellipsisPoolAddr, uint256 ellipsisPoolMinDy, address[] calldata path,
        address ptokenPoolAddr, address ptokenAddr, uint256 ptokenPoolMinDy,
        uint64 toChainId, bytes memory toAddress, bytes memory callData, uint256 deadline
    ) external virtual payable ensure(deadline) {
        IERC20(path[0]).safeTransferFrom(_msgSender(), address(this), amountIn);

        uint256 crossChainAmount = _exchangeTokensForTokensCrossChain(
            amountIn, ellipsisPoolAddr, ellipsisPoolMinDy, path
        );

        IERC20(path[1]).safeApprove(O3Wrapper, crossChainAmount);

        IWrapper(O3Wrapper).swapAndBridgeOut{value: msg.value}(
            ptokenPoolAddr, path[1], ptokenAddr, crossChainAmount, ptokenPoolMinDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function _exchangeTokensForTokensCrossChain(
        uint256 amountIn,
        address ellipsisPoolAddr,
        uint256 ellipsisPoolMinDy,
        address[] calldata path
    ) internal returns (uint256) {
        (uint256 amountOut, uint256 feeAmount) = _exchangeTokensForTokens(
            amountIn, ellipsisPoolAddr, ellipsisPoolMinDy, path
        );

        IERC20(path[1]).safeTransfer(feeCollector, feeAmount);

        return amountOut - feeAmount;
    }

    function exchangeETHForTokens(
        address ellipsisPoolAddr,
        address[] calldata path,
        uint256 minDy,
        address toAddress,
        uint256 deadline
    ) external payable ensure(deadline) {
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();

        require(path[0] == WETH, 'O3Aggregator: INVALID_PATH');
        uint256 amountOut = _ellipsisSwap(ellipsisPoolAddr, amountIn, path, minDy);
        uint256 feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        IERC20(path[1]).safeTransfer(feeCollector, feeAmount);
        IERC20(path[1]).safeTransfer(toAddress, amountOut - feeAmount);
    }

    function exchangeETHForTokensCrossChain(
        address ellipsisPoolAddr, uint256 ellipsisPoolMinDy, address[] calldata path,
        address ptokenPoolAddr, address ptokenAddr, uint256 ptokenPoolMinDy,
        uint256 fee, uint64 toChainId, bytes memory toAddress, bytes memory callData, uint256 deadline
    ) external payable ensure(deadline) {
        IWETH(WETH).deposit{value: msg.value - fee}();

        require(path[0] == WETH, 'O3Aggregator: INVALID_PATH');
        uint256 crossChainAmount = _exchangeTokensForTokensCrossChain(
            msg.value - fee, ellipsisPoolAddr, ellipsisPoolMinDy, path
        );

        IERC20(path[1]).safeApprove(O3Wrapper, crossChainAmount);

        IWrapper(O3Wrapper).swapAndBridgeOut{value: fee}(
            ptokenPoolAddr, path[1], ptokenAddr, crossChainAmount, ptokenPoolMinDy, deadline,
            toChainId, toAddress, callData
        );
    }

    function exchangeTokensForETH(
        uint256 amountIn,
        uint256 ellipsisPoolMinDy,
        address ellipsisPoolAddr,
        address[] calldata path,
        address toAddress,
        uint256 deadline
    ) external ensure(deadline) {
        require(path[1] == WETH, 'O3Aggregator: INVALID_PATH');

        IERC20(path[0]).safeTransferFrom(_msgSender(), address(this), amountIn);

        uint256 amountOut = _ellipsisSwap(ellipsisPoolAddr, amountIn, path, ellipsisPoolMinDy);
        uint256 feeAmount = amountOut * aggregatorFee / FEE_DENOMINATOR;
        emit LOG_AGG_SWAP(amountOut, feeAmount);

        IWETH(WETH).withdraw(amountOut);

        _sendETH(feeCollector, feeAmount);
        _sendETH(toAddress, amountOut - feeAmount);
    }

    function _sendETH(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}(new bytes(0));
        require(success, 'O3Aggregator: ETH_TRANSFER_FAILED');
    }

    function _getPoolTokenIndex(
        address ellipsisPoolAddr,
        address fromToken,
        address toToken
    ) internal returns (int128, int128) {
        int128 i;
        int128 j;
        bytes1 found = 0x00;

        for (uint256 idx = 0; idx < 8; idx++) {
            address coin = IBNBChainEllipsis(ellipsisPoolAddr).coins(idx);
            if (coin == fromToken) {
                i = int128(int256(idx));
                found |= bytes1(uint8(0x1));
            } else if (coin == toToken) {
                j = int128(int256(idx));
                found |= bytes1(uint8(0x2));
            }

            if (found == 0x03) {
                return (i, j);
            }
        }

        revert("token not pooled");
    }
}
