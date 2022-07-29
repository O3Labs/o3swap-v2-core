// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "../crossChain/interfaces/IDailyVolumeLimiter.sol";

contract DailyVolumeLimiter is Ownable, IDailyVolumeLimiter {
    mapping(address => uint256) public dayMap;
    mapping(address => uint256) public dailyVolumeMap;
    mapping(address => uint256) public volumeLimitMap;

    mapping(address => bool) private _authorizedCallers;

    event Accumulated(address token, uint256 volume);
    event SetLimit(address token, uint256 limit);
    event SetAuthorizedCaller(address caller, bool enabled);

    modifier onlyAuthorizedCaller() {
        require(_authorizedCallers[_msgSender()], "DailyVolumeLimiter: NOT_AUTHORIZED");
        _;
    }

    function volumeLimitEnabledFor(address _token) external view returns (bool) {
        return volumeLimitMap[_token] > 0;
    }

    function accumulate(address _token, uint256 newVolume) external onlyAuthorizedCaller returns (bool) {
        uint256 limit = volumeLimitMap[_token];
        if (limit == 0) {
            return true;
        }

        uint256 _day = block.timestamp / 1 days;
        if (_day != dayMap[_token]) {
            dailyVolumeMap[_token] = 0;
            dayMap[_token] = _day;
        }

        if (dailyVolumeMap[_token] + newVolume > limit) {
            return false;
        }

        dailyVolumeMap[_token] += newVolume;
        emit Accumulated(_token, dailyVolumeMap[_token]);

        return true;
    }

    function getDailyVolume(address _token) public view returns (uint256) {
        if (block.timestamp / 1 days != dayMap[_token]) {
            return 0;
        }

        return dailyVolumeMap[_token];
    }

    function isVolumeAllowed(address _token, uint256 newVolume) external view returns (bool) {
        uint256 limit = volumeLimitMap[_token];
        if (limit == 0) {
            return true;
        }

        return getDailyVolume(_token) + newVolume <= limit;
    }

    function isCallerAuthorized(address _caller) external view returns (bool) {
        return _authorizedCallers[_caller];
    }

    function setAuthorizedCaller(address _caller, bool _enabled) external onlyOwner {
        _authorizedCallers[_caller] = _enabled;
        emit SetAuthorizedCaller(_caller, _enabled);
    }

    function setLimit(address _token, uint256 _limit) external onlyOwner {
        volumeLimitMap[_token] = _limit;
        emit SetLimit(_token, _limit);
    }

    function setLimitBatch(address[] calldata tokens, uint256[] calldata limits) external onlyOwner {
        require(tokens.length == limits.length, "Inconsistent parameter lengths");

        for (uint256 i = 0; i < tokens.length; i++) {
            volumeLimitMap[tokens[i]] = limits[i];
            emit SetLimit(tokens[i], limits[i]);
        }
    }

    function updateVolume(address _token, uint256 vol) external onlyOwner {
        dailyVolumeMap[_token] = vol;
        emit Accumulated(_token, vol);
    }
}
