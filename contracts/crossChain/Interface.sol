pragma solidity ^0.8.0;

interface IEthCrossChainManager {
    function crossChain(uint64 _toChainId, bytes calldata _toContract, bytes calldata _method, bytes calldata _txData) external returns (bool);
}

interface IEthCrossChainManagerProxy {
    function getEthCrossChainManager() external view returns (address);
}

interface ICallProxy {
    function proxyCall( address ptoken, address receiver, uint256 amount, bytes memory callData) external returns(bool);
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
        bytes memory callData
    ) external returns(bool); 
}

interface IPool {
    function coins(uint256 index) external view returns(address);
    function getTokenIndex(address token) external view returns (uint8);
    function swap(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx, uint256 minDy, uint256 deadline) external returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}