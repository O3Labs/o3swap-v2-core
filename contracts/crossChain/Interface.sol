pragma solidity ^0.8.0;

interface IEthCrossChainManager {
    function crossChain(uint64 _toChainId, bytes calldata _toContract, bytes calldata _method, bytes calldata _txData) external returns (bool);
}

interface IEthCrossChainManagerProxy {
    function getEthCrossChainManager() external view returns (address);
}

interface ICallProxy {
    function proxyCall( address ptoken, address receiver, uint256 amount, bytes memory callee, bytes memory callData) external returns(bool);
}

interface IPToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IBridge {
    function bridgeOut(
        address fromAssetHash, 
        uint64 toChainId, 
        bytes memory toAddress, 
        uint256 amount,
        bytes memory callee,
        bytes memory callData
    ) external returns(bool); 
}