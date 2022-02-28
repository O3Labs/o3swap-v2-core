pragma solidity ^0.8.0;

import "./Interface.sol";
import "./Utils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Bridge is Ownable, IBridge {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    struct TxArgs {
        bytes toAssetHash;
        bytes toAddress;
        uint256 amount;
        bytes callData;
    }

    bool isInitialized = true;
    uint256 private constant FEE_DENOMINATOR = 10**10;
    uint256 public bridgeFeeRate;
    address public bridgeFeeCollector;
    address public callProxy;
    address public managerProxyContract;
    mapping(uint64 => bytes) public proxyHashMap;
    mapping(address => mapping(uint64 => bytes)) public assetHashMap;

    event setBridgeFeeEvent(uint256 rate, address feeCollector);
    event SetCallProxyEvent(address callProxy);
    event SetManagerProxyEvent(address manager);
    event BindProxyEvent(uint64 toChainId, bytes targetProxyHash);
    event BindAssetEvent(address fromAssetHash, uint64 toChainId, bytes targetProxyHash);
    event UnlockEvent(address toAssetHash, address toAddress, uint256 amount);
    event LockEvent(address fromAssetHash, address fromAddress, uint64 toChainId, bytes toAssetHash, bytes toAddress, uint256 amount);
    event BirdgeInEvent(address toAssetHash, address toAddress, uint256 amount, address callProxy, bytes callData);
    event BridgeOutEvent(address fromAssetHash, address fromAddress, uint64 toChainId, bytes toAssetHash, bytes toAddress, uint256 amount, uint256 fee, bytes callData);
    
    modifier onlyManagerContract() {
        IEthCrossChainManagerProxy ieccmp = IEthCrossChainManagerProxy(managerProxyContract);
        require(_msgSender() == ieccmp.getEthCrossChainManager(), "msgSender is not EthCrossChainManagerContract");
        _;
    }

    modifier initialization() {
        require(!isInitialized, "Already initialized");
        _;
        isInitialized = true;
    }

    function initialize(address initOwner) public initialization {
        _transferOwnership(initOwner);
    }

    function setBridgeFee(uint256 _rate, address _feeCollector) public onlyOwner {
        bridgeFeeRate = _rate;
        bridgeFeeCollector = _feeCollector;
        emit setBridgeFeeEvent(_rate, _feeCollector);
    }

    function setCallProxy(address _callProxy) onlyOwner public {
        callProxy = _callProxy;
        emit SetCallProxyEvent(_callProxy);
    }
    
    function setManagerProxy(address ethCCMProxyAddr) onlyOwner public {
        managerProxyContract = ethCCMProxyAddr;
        emit SetManagerProxyEvent(managerProxyContract);
    }
    
    function bindProxyHash(uint64 toChainId, bytes memory targetProxyHash) onlyOwner public returns (bool) {
        proxyHashMap[toChainId] = targetProxyHash;
        emit BindProxyEvent(toChainId, targetProxyHash);
        return true;
    }
    
    function bindAssetHash(address fromAssetHash, uint64 toChainId, bytes memory toAssetHash) onlyOwner public returns (bool) {
        assetHashMap[fromAssetHash][toChainId] = toAssetHash;
        emit BindAssetEvent(fromAssetHash, toChainId, toAssetHash);
        return true;
    }

    function bindProxyHashBatch(uint64[] memory toChainIds, bytes[] memory targetProxyHashs) onlyOwner public returns(bool) {
        require(toChainIds.length == targetProxyHashs.length, "Inconsistent parameter lengths");
        for (uint i=0; i<toChainIds.length; i++) {
            proxyHashMap[toChainIds[i]] = targetProxyHashs[i];
            emit BindProxyEvent(toChainIds[i], targetProxyHashs[i]);
        }
        return true;
    }

    function bindAssetHashBatch(address[] memory fromAssetHashs, uint64[] memory toChainIds, bytes[] memory toAssetHashs) onlyOwner public returns(bool) {
        require(toChainIds.length == fromAssetHashs.length, "Inconsistent parameter lengths");
        require(toChainIds.length == toAssetHashs.length, "Inconsistent parameter lengths");
        for (uint i=0; i<toChainIds.length; i++) {
            assetHashMap[fromAssetHashs[i]][toChainIds[i]] = toAssetHashs[i];
            emit BindAssetEvent(fromAssetHashs[i], toChainIds[i], toAssetHashs[i]);
        }
        return true;
    }

    function bridgeOut(
        address fromAssetHash, 
        uint64 toChainId, 
        bytes memory toAddress, 
        uint256 amount,
        bytes memory callData
    ) public override returns(bool) {
        require(amount != 0, "amount cannot be zero!");
        
        // check if bridge fee is required
        uint256 bridgeFee = 0;
        if (bridgeFeeRate == 0 || bridgeFeeCollector == address(0)) {
            // no bridge fee
        } else {
            bridgeFee = amount.mul(bridgeFeeRate).div(FEE_DENOMINATOR);
            amount = amount.sub(bridgeFee);
            require(_chargeFee(fromAssetHash, _msgSender(), bridgeFeeCollector, bridgeFee), "charge fee failed!");
        }

        require(_burnFrom(fromAssetHash, _msgSender(), amount), "transfer and burn asset from fromAddress to bridge contract failed!");

        bytes memory toAssetHash = assetHashMap[fromAssetHash][toChainId];
        require(toAssetHash.length != 0, "empty illegal toAssetHash");

        {            
            TxArgs memory txArgs = TxArgs({
                toAssetHash: toAssetHash,
                toAddress: toAddress,
                amount: amount,
                callData: callData
            });
            bytes memory txData = _serializeTxArgs(txArgs);

            IEthCrossChainManager eccm = IEthCrossChainManager(getCrossChainManagerAddress());

            bytes memory toProxyHash = proxyHashMap[toChainId];
            require(toProxyHash.length != 0, "empty illegal toProxyHash");
            require(eccm.crossChain(toChainId, toProxyHash, "bridgeIn", txData), "EthCrossChainManager crossChain executed error!");
        }

        emit LockEvent(fromAssetHash, _msgSender(), toChainId, toAssetHash, toAddress, amount);
        emit BridgeOutEvent(fromAssetHash, _msgSender(), toChainId, toAssetHash, toAddress, amount, bridgeFee, callData);

        return true;
    }

    function bridgeIn(bytes memory argsBs, bytes memory fromContractAddr, uint64 fromChainId) onlyManagerContract public returns (bool) {
        TxArgs memory args = _deserializeTxArgs(argsBs);

        require(fromContractAddr.length != 0, "from proxy contract address cannot be empty");
        require(Utils.equalStorage(proxyHashMap[fromChainId], fromContractAddr), "From Proxy contract address error!");

        require(args.toAssetHash.length != 0, "toAssetHash cannot be empty");
        address toAssetHash = Utils.bytesToAddress(args.toAssetHash);

        require(args.toAddress.length != 0, "toAddress cannot be empty");
        address toAddress = Utils.bytesToAddress(args.toAddress);

        if (args.callData.length == 0 || callProxy == address(0)) {
            require(_mintTo(toAssetHash, toAddress, args.amount), "mint ptoken to user failed");
        } else {
            require(_mintTo(toAssetHash, callProxy, args.amount), "mint ptoken to callProxy failed");
            require(ICallProxy(callProxy).proxyCall(toAssetHash, toAddress, args.amount, args.callData), "execute callData via callProxy failed");
        }

        emit UnlockEvent(toAssetHash, toAddress, args.amount);
        emit BirdgeInEvent(toAssetHash, toAddress, args.amount, callProxy, args.callData);

        return true;
    }

    function _chargeFee(address assetHash, address fromAddress, address toAddress, uint256 amount) internal returns (bool) {
        IERC20(assetHash).safeTransferFrom(fromAddress, toAddress, amount);
        return true;
    }

    function _burnFrom(address fromAssetHash, address fromAddress , uint256 amount) internal returns (bool) {
        IERC20(fromAssetHash).safeTransferFrom(fromAddress, address(this), amount);
        IPToken(fromAssetHash).burn(amount);
        return true;
    }

    function _mintTo(address toAssetHash, address toAddress, uint256 amount) internal returns (bool) {
        IPToken(toAssetHash).mint(toAddress, amount);
        return true;
    }

    function getCrossChainManagerAddress() public view returns(address) {
        IEthCrossChainManagerProxy eccmp = IEthCrossChainManagerProxy(managerProxyContract);
        return eccmp.getEthCrossChainManager();
    }
    
    function _serializeTxArgs(TxArgs memory args) internal pure returns (bytes memory) {
        bytes memory buff;
        buff = abi.encodePacked(
            Utils.WriteVarBytes(args.toAssetHash),
            Utils.WriteVarBytes(args.toAddress),
            Utils.WriteUint255(args.amount),
            Utils.WriteVarBytes(args.callData)
            );
        return buff;
    }

    function _deserializeTxArgs(bytes memory valueBs) internal pure returns (TxArgs memory) {
        TxArgs memory args;
        uint256 off = 0;
        (args.toAssetHash, off) = Utils.NextVarBytes(valueBs, off);
        (args.toAddress, off) = Utils.NextVarBytes(valueBs, off);
        (args.amount, off) = Utils.NextUint255(valueBs, off);
        (args.callData, off) = Utils.NextVarBytes(valueBs, off);
        return args;
    }

}