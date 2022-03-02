// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Utils.sol";
import "../access/Ownable.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ICallProxy.sol";
import "../swap/interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CallProxy is ICallProxy, Ownable {
    using SafeERC20 for IERC20;

    bool public externalCallEnabled;
    address public wethAddress;
    address public bridgeAddress;

    modifier onlyBridge() {
        require(msg.sender == bridgeAddress, "CallProxy: only Bridge can do this");
        _;
    }

    function setWETH(address _wethAddress) public onlyOwner {
        wethAddress = _wethAddress;
    }

    function setBridge(address _bridgeAddress) public onlyOwner {
        bridgeAddress = _bridgeAddress;
    }

    function enableExternalCall() public onlyOwner {
        externalCallEnabled = true;
    }

    function disableExternalCall() public onlyOwner {
        externalCallEnabled = false;
    }

    function proxyCall(
        address ptoken,
        address receiver,
        uint256 amount,
        bytes memory callData
    ) public override onlyBridge returns(bool) {
        (bytes1 tag, ) = Utils.NextByte(callData, 0);
        if (tag == 0x01) { // swap
            // decode data
            try this.decodeCallDataForSwap(callData)
            returns(address poolAddress,bool unwrapETH,bool swapAll,uint8 tokenIndexFrom, uint8 tokenIndexTo,uint256 dx,uint256 dy,uint256 deadline)
            {
                // check swap amount
                if (swapAll) {
                    dx = amount;
                }

                // check from token address
<<<<<<< HEAD
                if (IPool(poolAddress).coins(tokenIndexFrom) != ptoken) {
                    IERC20(ptoken).safeTransfer(receiver, amount);
=======
                if (address(IPool(poolAddress).coins(tokenIndexFrom)) != ptoken) {
                    IERC20(ptoken).transfer(receiver, amount);
>>>>>>> o3/dev
                    return true;
                }

                // do swap
                dy = _swap(poolAddress, tokenIndexFrom, tokenIndexTo, dx, dy, deadline);

                // check if unwrap ETH is needed
                if (unwrapETH && address(IPool(poolAddress).coins(tokenIndexTo)) == wethAddress && dy != 0) {
                    IWETH(wethAddress).withdraw(dy);
                    payable(receiver).transfer(dy);
                } else if (dy != 0) {
<<<<<<< HEAD
                    IERC20 targetToken = IERC20(IPool(poolAddress).coins(tokenIndexTo));
                    targetToken.safeTransfer(receiver, dy);
=======
                    IERC20 targetToken = IPool(poolAddress).coins(tokenIndexTo);
                    targetToken.transfer(receiver, dy);
>>>>>>> o3/dev
                }
            } catch { /* do nothing if data is invalid*/ }
        } else if (externalCallEnabled && tag == 0x02) { // external call
            try this.decodeCallDataForExternalCall(callData) returns(address callee,bytes memory data) {
                // approve ptoken
                IERC20(ptoken).safeApprove(callee, 0);
                IERC20(ptoken).safeApprove(callee, amount);

                // do external call
                callee.call(data);
            } catch { /* do nothing if data is invalid*/ }
        } else { /* unknown tag, do nothing */ }

        // transfer the remaining ptoken to receiver
        uint256 balance = IERC20(ptoken).balanceOf(address(this));
        if (balance != 0) {
<<<<<<< HEAD
            IERC20(ptoken).safeTransfer(receiver, balance);
=======
            IERC20(ptoken).transfer(receiver, balance);
>>>>>>> o3/dev
        }
        return true;
    }

    function _swap(address poolAddress, uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx, uint256 minDy, uint256 deadline) internal returns(uint256 dy) {
        IERC20 tokenFrom = IERC20(IPool(poolAddress).coins(tokenIndexFrom));
        tokenFrom.safeApprove(poolAddress, 0);
        tokenFrom.safeApprove(poolAddress, dx);
        try IPool(poolAddress).swap(tokenIndexFrom, tokenIndexTo, dx, minDy, deadline) returns(uint256 _dy) {
            dy = _dy;
        } catch {
            dy = 0;
        }
    }

    function decodeCallDataForSwap(bytes memory callData) public pure returns (
        address poolAddress,
        bool unwrapETH,
        bool swapAll,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ){
        bytes memory poolAddressBytes;
        uint8 boolPair;
        uint256 off = 1; // dismiss tag
        (poolAddressBytes, off) = Utils.NextVarBytes(callData, off);
        poolAddress = Utils.bytesToAddress(poolAddressBytes);

        (boolPair, off) = Utils.NextUint8(callData, off);
        (unwrapETH, swapAll) = _uint8ToBoolPair(boolPair);

        (tokenIndexFrom, off) = Utils.NextUint8(callData, off);

        (tokenIndexTo, off) = Utils.NextUint8(callData, off);

        (dx, off) = Utils.NextUint255(callData, off);

        (minDy, off) = Utils.NextUint255(callData, off);

        (deadline, off) = Utils.NextUint255(callData, off);
    }
    function encodeArgsForSwap(
        bytes memory poolAddress,
        bool unwrapETH,
        bool swapAll,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) public pure returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            Utils.WriteByte(0x01),
            Utils.WriteVarBytes(poolAddress),
            Utils.WriteUint8(_boolPairToUint8(unwrapETH, swapAll)),
            Utils.WriteUint8(tokenIndexFrom),
            Utils.WriteUint8(tokenIndexTo),
            Utils.WriteUint255(dx),
            Utils.WriteUint255(minDy),
            Utils.WriteUint255(deadline)
        );
        return buff;
    }


    function decodeCallDataForExternalCall(bytes memory callData) public pure returns(
        address callee,
        bytes memory data
    ){
        bytes memory calleeAddressBytes;
        uint256 off = 1; // dismiss tag
        (calleeAddressBytes, off) = Utils.NextVarBytes(callData, off);
        callee = Utils.bytesToAddress(calleeAddressBytes);

        (data, off) = Utils.NextVarBytes(callData, off);
    }
    function encodeArgsForExternalCall(
        bytes memory callee,
        bytes memory data
    ) public pure returns(bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            Utils.WriteByte(0x02),
            Utils.WriteVarBytes(callee),
            Utils.WriteVarBytes(data)
        );
        return buff;
    }


    function _boolPairToUint8(bool flag1, bool flag2) internal pure returns(uint8 res) {
        assembly{
            res := add(flag1, mul(flag2, 2))
        }
    }
    function _uint8ToBoolPair(uint8 raw) internal pure returns(bool flag1, bool flag2) {
        assembly{
            flag1 := mod(raw, 2)
            flag2 := div(raw, 2)
        }
    }
}