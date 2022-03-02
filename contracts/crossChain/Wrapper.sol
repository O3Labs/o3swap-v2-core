// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IBridge.sol";
import "../swap/interfaces/IPool.sol";
import "../assets/interfaces/IPToken.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Wrapper is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public bridge;
    address public feeCollector;
    address public wethAddress;

    event PolyWrapperLock(address indexed fromAsset, address indexed sender, uint64 toChainId, bytes toAddress, uint net, uint fee, uint id);

    modifier onlyFeeCollector {
        require(_msgSender() == feeCollector, "Not fee collector");
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setBridgeContract(address _bridge) public onlyOwner {
        bridge = _bridge;
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
        feeCollector = _feeCollector;
    }

    function setWETHAddress(address _weth) public onlyOwner {
        wethAddress = _weth;
    }

    function extractFee() public onlyFeeCollector {
        payable(feeCollector).transfer(address(this).balance);
    }

    function rescueFund(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function bridgeOut(
        address pTokenAddress,
        uint256 amount,
        uint64 toChainId,
        bytes memory toAddress,
        bytes memory callData
    ) public payable nonReentrant whenNotPaused returns(bool) {
        // check
        require(toAddress.length !=0, "empty toAddress");
        address addr;
        assembly { addr := mload(add(toAddress,0x14)) }
        require(addr != address(0),"zero toAddress");

        // pull
        IERC20(pTokenAddress).safeTransferFrom(_msgSender(), address(this), amount);

        // push
        IERC20(pTokenAddress).safeApprove(bridge, 0);
        IERC20(pTokenAddress).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(pTokenAddress, toChainId, toAddress, amount, callData), "lock erc20 fail");

        // log
        emit PolyWrapperLock(pTokenAddress, _msgSender(), toChainId, toAddress, amount, msg.value, 1);

        return true;

    }

    function swapAndBridgeOut(
        address poolAddress, address tokenFrom, address tokenTo, uint256 dx, uint256 minDy, uint256 deadline,   // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData                                         // args for bridge
    ) public payable nonReentrant whenNotPaused returns(bool) {
        uint256 balanceBefore = IERC20(tokenTo).balanceOf(address(this));
        {
            // check
            require(toAddress.length !=0, "empty toAddress");
            address addr;
            assembly { addr := mload(add(toAddress,0x14)) }
            require(addr != address(0),"zero toAddress");
        }
        {
            // pull
            IERC20(tokenFrom).safeTransferFrom(_msgSender(), address(this), dx);
        }
        {
            // swap
            IERC20(tokenFrom).safeApprove(poolAddress, 0);
            IERC20(tokenFrom).safeApprove(poolAddress, dx);
            IPool pool = IPool(poolAddress);
            pool.swap(pool.getTokenIndex(tokenFrom), pool.getTokenIndex(tokenTo), dx, minDy, deadline);
        }

        // push
        uint256 amount = IERC20(tokenTo).balanceOf(address(this)).sub(balanceBefore);
        IERC20(tokenTo).safeApprove(bridge, 0);
        IERC20(tokenTo).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(tokenTo, toChainId, toAddress, amount, callData), "lock erc20 fail");

        // log
        emit PolyWrapperLock(tokenTo, _msgSender(), toChainId, toAddress, amount, msg.value, 2);

        return true;
    }

    function swapAndBridgeOutNativeToken(
        address poolAddress, address tokenTo, uint256 dx, uint256 minDy, uint256 deadline,     // args for swap
        uint64 toChainId, bytes memory toAddress, bytes memory callData                        // args for bridge
    ) public payable nonReentrant whenNotPaused returns(bool) {
        require(msg.value >= dx, "insufficient fund");
        uint256 balanceBefore = IERC20(tokenTo).balanceOf(address(this));
        {
            // check
            require(toAddress.length !=0, "empty toAddress");
            address addr;
            assembly { addr := mload(add(toAddress,0x14)) }
            require(addr != address(0),"zero toAddress");
        }
        {
            // deposit
            IWETH(wethAddress).deposit{value: dx}();
        }
        {
            // swap
            IERC20(wethAddress).safeApprove(poolAddress, 0);
            IERC20(wethAddress).safeApprove(poolAddress, dx);
            IPool pool = IPool(poolAddress);
            pool.swap(pool.getTokenIndex(wethAddress), pool.getTokenIndex(tokenTo), dx, minDy, deadline);
        }

        // push
        uint256 amount = IERC20(tokenTo).balanceOf(address(this)).sub(balanceBefore);
        IERC20(tokenTo).safeApprove(bridge, 0);
        IERC20(tokenTo).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(tokenTo, toChainId, toAddress, amount, callData), "lock erc20 fail");

        // log
        emit PolyWrapperLock(tokenTo, _msgSender(), toChainId, toAddress, amount, msg.value.sub(dx), 3);

        return true;
    }

    function depositAndBridgeOut(
        address originalToken,
        address pTokenAddress,
        uint256 amount,
        uint64 toChainId,
        bytes memory toAddress,
        bytes memory callData
    ) public payable nonReentrant whenNotPaused returns(bool) {
        {
            // check
            require(IPToken(pTokenAddress).tokenUnderlying() == originalToken, "invalid ptoken / originalToken");
            require(toAddress.length !=0, "empty toAddress");
            address addr;
            assembly { addr := mload(add(toAddress,0x14)) }
            require(addr != address(0),"zero toAddress");
        }
        {
            // pull
            IERC20(originalToken).safeTransferFrom(_msgSender(), address(this), amount);
        }
        {
            // deposit
            IERC20(originalToken).safeApprove(pTokenAddress, 0);
            IERC20(originalToken).safeApprove(pTokenAddress, amount);
            IPToken(pTokenAddress).deposit(address(this), amount);
        }

        // push
        IERC20(pTokenAddress).safeApprove(bridge, 0);
        IERC20(pTokenAddress).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(pTokenAddress, toChainId, toAddress, amount, callData), "lock erc20 fail");

        // log
        emit PolyWrapperLock(pTokenAddress, _msgSender(), toChainId, toAddress, amount, msg.value, 4);

        return true;
    }

    function depositAndBridgeOutNativeToken(
        address pTokenAddress,
        uint256 amount,
        uint64 toChainId,
        bytes memory toAddress,
        bytes memory callData
    ) public payable nonReentrant whenNotPaused returns(bool) {
        require(msg.value >= amount, "insufficient fund");
        {
            // check
            require(IPToken(pTokenAddress).tokenUnderlying() == wethAddress, "invalid ptoken");
            require(toAddress.length !=0, "empty toAddress");
            address addr;
            assembly { addr := mload(add(toAddress,0x14)) }
            require(addr != address(0),"zero toAddress");
        }
        {
            // deposit & deposit
            IWETH(wethAddress).deposit{value: amount}();
            IERC20(wethAddress).safeApprove(pTokenAddress, 0);
            IERC20(wethAddress).safeApprove(pTokenAddress, amount);
            IPToken(pTokenAddress).deposit(address(this), amount);
        }

        // push
        IERC20(pTokenAddress).safeApprove(bridge, 0);
        IERC20(pTokenAddress).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(pTokenAddress, toChainId, toAddress, amount, callData), "lock erc20 fail");

        // log
        emit PolyWrapperLock(pTokenAddress, _msgSender(), toChainId, toAddress, amount, msg.value.sub(amount), 5);

        return true;
    }
}