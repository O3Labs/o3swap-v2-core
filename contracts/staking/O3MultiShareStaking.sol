// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "../assets/interfaces/IO3.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract O3MultiShareStaking is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct StakingRecord {
        uint blockTimestamp;
        uint staked;
        uint[] totalProfits;
    }

    event LOG_STAKE (
        address indexed staker,
        uint stakeAmount
    );

    event LOG_UNSTAKE (
        address indexed staker,
        uint withdrawAmount
    );

    event LOG_CLAIM_PROFITS (
        address indexed staker,
        uint[] profit
    );

    event LOG_CALL (
        bytes4 indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, _msgSender(), _msgData());
        _;
    }

    address public StakingToken;
    address[] public shareTokens;

    address public O3Token;

    uint public startStakingBlockTimestamp;
    uint public startClaimBlockTimestamp;
    uint[] public endProfitBlockTimestamp;

    uint public totalStaked;

    uint[] private _sharePerSecond;
    mapping(address => StakingRecord) private _stakingRecords;
    mapping(uint => uint[]) private _unitProfitAccumu;

    uint[] private _unitProfits;
    uint private _upBlockTimestamp;

    bool private _stakingPaused;
    bool private _withdarawPaused;
    bool private _claimProfitPaused;

    uint public constant ONE = 10**18;

    constructor(
        address _stakingToken,
        address _o3Token,
        address[] memory _shareTokens,
        uint _startStakingBlockTimestamp,
        uint _startClaimBlockTimestamp,
        uint[] memory _endProfitBlockTimestamp
    ) {
        require(_stakingToken != address(0), "O3Staking: ZERO_STAKING_ADDRESS");
        require(_o3Token != address(0), "O3Staking: ZERO_O3TOKEN_ADDRESS");
        require(_shareTokens.length != 0, "O3Staking: ZERO_SHARE_TOKENS");
        require(_startClaimBlockTimestamp >= _startStakingBlockTimestamp, "O3Staking: INVALID_START_CLAIM_BLOCK_TIMESTAMP");
        require(_shareTokens.length == _endProfitBlockTimestamp.length, "O3Staking: INCONSISTENT_PARAMETER_LENGTHS");

        for (uint i = 0; i < _endProfitBlockTimestamp.length; i++) {
            if (_endProfitBlockTimestamp[i] != 0) {
                require(_endProfitBlockTimestamp[i] > _startStakingBlockTimestamp, "O3Staking: INVALID_END_PROFIT_BLOCK_TIMESTAMP");
            }
        }

        StakingToken = _stakingToken;
        O3Token = _o3Token;
        shareTokens = _shareTokens;
        startStakingBlockTimestamp = _startStakingBlockTimestamp;
        startClaimBlockTimestamp = _startClaimBlockTimestamp;
        endProfitBlockTimestamp = _endProfitBlockTimestamp;

        _unitProfits = new uint[](_shareTokens.length);
        _sharePerSecond = new uint[](_shareTokens.length);
    }

    function getShareTokens() external view returns (address[] memory) {
        return shareTokens;
    }

    function getTotalProfit(address staker) external view returns (uint[] memory) {
        return _getTotalProfit(staker);
    }

    function _getTotalProfit(address staker) internal view returns (uint[] memory) {
        if (block.timestamp <= startStakingBlockTimestamp) {
            return new uint[](shareTokens.length);
        }

        uint[] memory currentProfitAccumu = _unitProfitAccumu[block.timestamp];
        if (currentProfitAccumu.length == 0 ) {
            currentProfitAccumu = new uint[](shareTokens.length);
        }

        if (_upBlockTimestamp < block.timestamp) {
            for (uint i = 0; i < shareTokens.length; i++)
            {
                uint tsOffset = _getTsOffset(i);
                uint unitProfitIncrease = _unitProfits[i].mul(tsOffset);
                currentProfitAccumu[i] = _getUnitProfitAccumuValue(_upBlockTimestamp, i).add(unitProfitIncrease);
            }
        }

        StakingRecord storage rec = _stakingRecords[staker];

        uint[] memory profits = new uint[](shareTokens.length);
        for (uint i = 0; i < shareTokens.length; i++) {
            uint preUnitProfit = _getUnitProfitAccumuValue(rec.blockTimestamp, i);
            uint currentProfit = (currentProfitAccumu[i].sub(preUnitProfit)).mul(rec.staked).div(ONE);

            uint preProfit = 0;
            if (rec.totalProfits.length > 0) {
                preProfit = rec.totalProfits[i];
            }

            profits[i] = preProfit.add(currentProfit);
        }

        return profits;
    }

    function _getTsOffset(uint index) internal view returns (uint) {
        require(_upBlockTimestamp <= block.timestamp, "invalid 'getTsOffset' call");

        uint tsOffset = block.timestamp.sub(_upBlockTimestamp);
        if (endProfitBlockTimestamp[index] > 0) {
            if (_upBlockTimestamp >= endProfitBlockTimestamp[index]) {
                tsOffset = 0;
            } else if (block.timestamp >= endProfitBlockTimestamp[index]) {
                tsOffset = endProfitBlockTimestamp[index].sub(_upBlockTimestamp);
            }
        }

        return tsOffset;
    }

    function getStakingAmount(address staker) external view returns (uint) {
        StakingRecord storage rec = _stakingRecords[staker];
        return rec.staked;
    }

    function getSharePerSecondArray() external view returns (uint[] memory) {
        uint[] memory result = new uint[](shareTokens.length);

        for (uint i = 0; i < shareTokens.length; i++) {
            if (endProfitBlockTimestamp[i] != 0 && block.timestamp >= endProfitBlockTimestamp[i]) {
                result[i] = 0;
            } else {
                result[i] = _sharePerSecond[i];
            }
        }

        return result;
    }

    function setStakingToke(address _token) external onlyOwner _logs_ {
        StakingToken = _token;
    }

    function setSharePerSecond(uint index, uint sharePerSecond) external onlyOwner _logs_ {
        require(index < _sharePerSecond.length, "O3Staking: index out of range");

        _sharePerSecond[index] = sharePerSecond;
        _updateUnitProfitStates();
    }

    function setSharePerSecondBatch(uint[] calldata indexes, uint[] calldata sharePerSecondArray) external onlyOwner _logs_ {
        require(sharePerSecondArray.length == shareTokens.length, "O3Staking: INCONSISTENT_PARAMETER_LENGTHS");
        require(indexes.length == sharePerSecondArray.length, "O3Staking: INCONSISTENT_PARAMETER_LENGTHS");

        for (uint i = 0; i < sharePerSecondArray.length; i++) {
            _sharePerSecond[indexes[i]] = sharePerSecondArray[i];
        }

        _updateUnitProfitStates();
    }

    function setStartClaimBlockTime(uint _startClaimBlockTimestamp) external onlyOwner _logs_ {
        startClaimBlockTimestamp = _startClaimBlockTimestamp;
    }

    function stake(uint amount) external nonReentrant _logs_ {
        require(!_stakingPaused, "O3Staking: STAKING_PAUSED");
        require(amount > 0, "O3Staking: INVALID_STAKING_AMOUNT");

        totalStaked = totalStaked.add(amount);

        StakingRecord storage rec = _stakingRecords[_msgSender()];

        uint[] memory totalProfits = _updateUPStateAndGetTotalProfit(_msgSender());
        _updateUserStakingRecord(_msgSender(), rec.staked.add(amount), totalProfits);

        emit LOG_STAKE(_msgSender(), amount);

        _pullToken(StakingToken, _msgSender(), amount);
    }

    function unstake(uint amount) external nonReentrant _logs_ {
        require(!_withdarawPaused, "O3Staking: UNSTAKE_PAUSED");

        StakingRecord storage rec = _stakingRecords[_msgSender()];

        require(amount > 0, "O3Staking: ZERO_UNSTAKE_AMOUNT");
        require(amount <= rec.staked, "O3Staking: UNSTAKE_AMOUNT_EXCEEDED");

        totalStaked = totalStaked.sub(amount);

        uint[] memory totalProfits = _updateUPStateAndGetTotalProfit(_msgSender());
        _updateUserStakingRecord(_msgSender(), rec.staked.sub(amount), totalProfits);

        emit LOG_UNSTAKE(_msgSender(), amount);

        _pushToken(StakingToken, _msgSender(), amount);
    }

    function claimProfit() external nonReentrant _logs_ {
        require(!_claimProfitPaused, "O3Staking: CLAIM_PROFIT_PAUSED");
        require(block.timestamp >= startClaimBlockTimestamp, "O3Staking: CLAIM_NOT_STARTED");

        uint[] memory totalProfits = _updateUPStateAndGetTotalProfit(_msgSender());
        bool canClaim = false;
        for (uint i = 0; i < shareTokens.length; i++) {
            if (totalProfits[i] > 0) {
                canClaim = true;
            }
        }

        require(canClaim, "O3Staking: ZERO_PROFIT");

        StakingRecord storage rec = _stakingRecords[_msgSender()];
        _updateUserStakingRecord(_msgSender(), rec.staked, new uint[](shareTokens.length));

        emit LOG_CLAIM_PROFITS(_msgSender(), totalProfits);

        _pushShareTokens(_msgSender(), totalProfits);
    }

    function _updateUPStateAndGetTotalProfit(address staker) internal returns (uint[] memory) {
        _updateUnitProfitStates();
        return _getTotalProfit(staker);
    }

    function _updateUserStakingRecord(address staker, uint staked, uint[] memory totalProfits) internal {
        _stakingRecords[staker].staked = staked;
        _stakingRecords[staker].totalProfits = totalProfits;

        if (block.timestamp < startStakingBlockTimestamp) {
            _stakingRecords[staker].blockTimestamp = startStakingBlockTimestamp;
        } else {
            _stakingRecords[staker].blockTimestamp = block.timestamp;
        }
    }

    function _updateUnitProfitStates() internal {
        for (uint i = 0; i < shareTokens.length; i++) {
            _updateUnitProfitState(i);
        }

        if (_upBlockTimestamp < block.timestamp) {
            _upBlockTimestamp = block.timestamp;
        }
    }

    function _updateUnitProfitState(uint index) internal {
        uint currTs = block.timestamp;

        if (_upBlockTimestamp >= currTs) {
            _updateUnitProfit(index);
            return;
        }

        if (_unitProfitAccumu[currTs].length == 0 ) {
            _unitProfitAccumu[currTs] = new uint[](shareTokens.length);
        }

        uint tsOffset = _getTsOffset(index);
        uint unitStakeProfitIncrease = _unitProfits[index].mul(tsOffset);
        _unitProfitAccumu[currTs][index] = _getUnitProfitAccumuValue(_upBlockTimestamp, index).add(unitStakeProfitIncrease);

        if (currTs <= startStakingBlockTimestamp) {
            _upBlockTimestamp = startStakingBlockTimestamp;
        }

        _updateUnitProfit(index);
    }

    function _getUnitProfitAccumuValue(uint timestamp, uint index) internal view returns (uint) {
        uint[] memory arr = _unitProfitAccumu[timestamp];
        if (arr.length == 0) {
            return 0;
        }

        return arr[index];
    }

    function _updateUnitProfit(uint index) internal {
        if (totalStaked == 0) {
            _unitProfits[index] = 0;
            return;
        }

        if (endProfitBlockTimestamp[index] > 0 && block.timestamp > endProfitBlockTimestamp[index]) {
            _unitProfits[index] = 0;
            return;
        }

        _unitProfits[index] = _sharePerSecond[index].mul(ONE).div(totalStaked);
    }

    function pauseStaking() external onlyOwner _logs_ {
        _stakingPaused = true;
    }

    function unpauseStaking() external onlyOwner _logs_ {
        _stakingPaused = false;
    }

    function pauseUnstake() external onlyOwner _logs_ {
        _withdarawPaused = true;
    }

    function unpauseUnstake() external onlyOwner _logs_ {
        _withdarawPaused = false;
    }

    function pauseClaimProfit() external onlyOwner _logs_ {
        _claimProfitPaused = true;
    }

    function unpauseClaimProfit() external onlyOwner _logs_ {
        _claimProfitPaused = false;
    }

    function rescue(address token, address to) external onlyOwner _logs_ {
        require(token != StakingToken, "O3Staking: RESCUE_NOT_ALLOWED");
        uint balance = IERC20(token).balanceOf(address(this));
        _pushToken(token, to, balance);
    }

    function _pushToken(address token, address to, uint amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function _pushShareTokens(address to, uint[] memory amounts) internal {
        for (uint i = 0; i < shareTokens.length; i++) {
            if (amounts[i] == 0) {
                continue;
            }

            if (shareTokens[i] == O3Token) {
                IO3(O3Token).mintLockedToken(to, amounts[i]);
            } else {
                IERC20(shareTokens[i]).safeTransfer(to, amounts[i]);
            }
        }
    }

    function _pullToken(address token, address from, uint amount) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
    }
}
