pragma solidity ^0.8.0;

import "./Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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

    function extractFee() public onlyFeeCollector {
        payable(feeCollector).transfer(address(this).balance);
    }

    function rescueFund(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(_msgSender(), token.balanceOf(address(this)));
    }

    function bridgeOut(
        address fromAsset, 
        uint64 toChainId, 
        bytes memory toAddress, 
        uint256 amount,
        bytes memory callee,
        bytes memory callData
    ) public payable nonReentrant whenNotPaused returns(bool) {
        // check
        require(toAddress.length !=0, "empty toAddress");
        address addr;
        assembly { addr := mload(add(toAddress,0x14)) }
        require(addr != address(0),"zero toAddress");

        // pull
        IERC20(fromAsset).safeTransferFrom(_msgSender(), address(this), amount);

        // push
        IERC20(fromAsset).safeApprove(bridge, 0);
        IERC20(fromAsset).safeApprove(bridge, amount);
        require(IBridge(bridge).bridgeOut(fromAsset, toChainId, toAddress, amount, callee, callData), "lock erc20 fail");
        
        // log
        emit PolyWrapperLock(fromAsset, _msgSender(), toChainId, toAddress, amount, msg.value, 0);

    }

}