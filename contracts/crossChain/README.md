## CrossChain contracts

### Bridge.sol
Core contract for crossChain
+ What can/should admin do:
    + setBridgeFee(**optional*)
    + setCallProxy
    + setManagerProxy
    + bindProxyHash / bindProxyHashBatch
    + bindAssetHash / bindAssetHashBatch
+ What can user do: 
    + bridgeOut
+ What can CrossChainManager do: 
    + bridgeIn

### CallProxy.sol
Isolate external calls from core contracts.
+ What can/should admin do:
    + setWETH
    + setBridge
    + enableExternalCall / disableExternalCall(**when needed*)
+ What can Bridge contract do:
    + proxyCall
+ Codec tools:
    + encodeArgsForSwap / decodeCallDataForSwap
    + encodeArgsForExternalCall / decodeCallDataForExternalCall

### Wrapper.sol
Charge fee
+ What can/should admin do:
    + pause / unpause(**when needed*)
    + setBridgeContract
    + setFeeCollector(**optional*)
    + setWETHAddress
    + rescueFund(**when needed*)
+ What can feeCollector do:
    + extractFee
+ What can user do:
    + bridgeOut
    + swapAndBridgeOut
    + swapAndBridgeOutNativeToken

### How to Cross Chain
1) Admin Configure the corresponding contracts
2) Determines the operation on target chain, encodes the call data via CallProxy.sol
3) Approve token to source chain Wrapper.sol (not needed for native token)
4) bridgeOut / swapAndBridgeOut / swapAndBridgeOutNativeToken via Wrapper.sol