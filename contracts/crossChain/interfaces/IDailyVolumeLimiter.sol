// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

interface IDailyVolumeLimiter {
    function volumeLimitMap(address _token) external returns (uint256);
    function volumeLimitEnabledFor(address _token) external returns (bool);
    function accumulate(address _token, uint256 newVolume) external returns (bool);
    function getDailyVolume(address _token) external returns (uint256);
    function isVolumeAllowed(address _token, uint256 newVolume) external returns (bool);

    function setAuthorizedCaller(address _caller, bool _enabled) external;
    function isCallerAuthorized(address _caller) external returns (bool);
    function setLimit(address _token, uint256 _limit) external;
    function updateVolume(address _token, uint256 vol) external;
}
