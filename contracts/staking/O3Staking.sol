// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "../assets/interfaces/IO3.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract O3Staking is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct StakingRecord {
        address staker;
        uint blockTimestamp;
        uint staked;
        uint totalProfit;
    }

    event LOG_STAKE (
        address indexed staker,
        uint stakeAmount
    );

    event LOG_UNSTAKE (
        address indexed staker,
        uint withdrawAmount
    );

    event LOG_CLAIM_PROFIT (
        address indexed staker,
        uint profit
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

    // Only pool LP tokens can be staking token, so the contract
    // will never be a proxy contract with multiple entry points.
    address public StakingToken;

    address public O3Token;
    uint public startStakingBlockTimestamp;
    uint public startUnstakeBlockTimestamp;
    uint public startClaimBlockTimestamp;
    uint public totalStaked;

    mapping(address => StakingRecord) private _stakingRecords;
    mapping(uint => uint) private _unitProfitAccumu;

    uint private _unitProfit; // Latest unit profit.
    uint private _upBlockTimestamp; // The block timestamp `_unitProfit` refreshed.

    uint private _sharePerSecond;
    bool private _stakingPaused;
    bool private _withdarawPaused;
    bool private _claimProfitPaused;

    uint public constant ONE = 10**18;

    constructor(
        address _stakingToken,
        address _o3Token,
        uint _startStakingBlockTimestamp,
        uint _startUnstakeBlockTimestamp,
        uint _startClaimBlockTimestamp
    ) {
        require(_stakingToken != address(0), "O3Staking: ZERO_STAKING_ADDRESS");
        require(_o3Token != address(0), "O3Staking: ZERO_O3TOKEN_ADDRESS");
        require(_startClaimBlockTimestamp >= _startStakingBlockTimestamp, "O3Staking: INVALID_START_CLAIM_BLOCK_TIMESTAMP");

        StakingToken = _stakingToken;
        O3Token = _o3Token;
        startStakingBlockTimestamp = _startStakingBlockTimestamp;
        startUnstakeBlockTimestamp = _startUnstakeBlockTimestamp;
        startClaimBlockTimestamp = _startClaimBlockTimestamp;
    }

    function getTotalProfit(address staker) external view returns (uint) {
        if (block.timestamp <= startStakingBlockTimestamp) {
            return 0;
        }

        uint currentProfitAccumu = _unitProfitAccumu[block.timestamp];
        if (_upBlockTimestamp < block.timestamp) {
            uint unitProfitIncrease = _unitProfit.mul(block.timestamp.sub(_upBlockTimestamp));
            currentProfitAccumu = _unitProfitAccumu[_upBlockTimestamp].add(unitProfitIncrease);
        }

        StakingRecord storage rec = _stakingRecords[staker];

        uint preUnitProfit = _unitProfitAccumu[rec.blockTimestamp];
        uint currentProfit = (currentProfitAccumu.sub(preUnitProfit)).mul(rec.staked).div(ONE);

        return rec.totalProfit.add(currentProfit);
    }

    function getStakingAmount(address staker) external view returns (uint) {
        StakingRecord storage rec = _stakingRecords[staker];
        return rec.staked;
    }

    function getSharePerSecond() external view returns (uint) {
        return _sharePerSecond;
    }

    function setStakingToken(address _token) external onlyOwner _logs_ {
        StakingToken = _token;
    }

    function setSharePerSecond(uint sharePerSecond) external onlyOwner _logs_ {
        _sharePerSecond = sharePerSecond;
        _updateUnitProfitState();
    }

    function setStartUnstakeBlockTime(uint _startUnstakeBlockTimestamp) external onlyOwner _logs_ {
        startUnstakeBlockTimestamp = _startUnstakeBlockTimestamp;
    }

    function setStartClaimBlockTime(uint _startClaimBlockTimestamp) external onlyOwner _logs_ {
        startClaimBlockTimestamp = _startClaimBlockTimestamp;
    }

    function stake(uint amount) external nonReentrant _logs_ {
        require(!_stakingPaused, "O3Staking: STAKING_PAUSED");
        require(amount > 0, "O3Staking: INVALID_STAKING_AMOUNT");

        totalStaked = amount.add(totalStaked);
        _updateUnitProfitState();

        StakingRecord storage rec = _stakingRecords[_msgSender()];

        uint userTotalProfit = _settleCurrentUserProfit(_msgSender());
        _updateUserStakingRecord(_msgSender(), rec.staked.add(amount), userTotalProfit);

        emit LOG_STAKE(_msgSender(), amount);

        _pullToken(StakingToken, _msgSender(), amount);
    }

    function unstake(uint amount) external nonReentrant _logs_ {
        require(!_withdarawPaused, "O3Staking: UNSTAKE_PAUSED");
        require(block.timestamp >= startUnstakeBlockTimestamp, "O3Staking: UNSTAKE_NOT_STARTED");

        StakingRecord storage rec = _stakingRecords[_msgSender()];

        require(amount > 0, "O3Staking: ZERO_UNSTAKE_AMOUNT");
        require(amount <= rec.staked, "O3Staking: UNSTAKE_AMOUNT_EXCEEDED");

        totalStaked = totalStaked.sub(amount);
        _updateUnitProfitState();

        uint userTotalProfit = _settleCurrentUserProfit(_msgSender());
        _updateUserStakingRecord(_msgSender(), rec.staked.sub(amount), userTotalProfit);

        emit LOG_UNSTAKE(_msgSender(), amount);

        _pushToken(StakingToken, _msgSender(), amount);
    }

    function claimProfit() external nonReentrant _logs_ {
        require(!_claimProfitPaused, "O3Staking: CLAIM_PROFIT_PAUSED");
        require(block.timestamp >= startClaimBlockTimestamp, "O3Staking: CLAIM_NOT_STARTED");

        uint totalProfit = _getTotalProfit(_msgSender());
        require(totalProfit > 0, "O3Staking: ZERO_PROFIT");

        StakingRecord storage rec = _stakingRecords[_msgSender()];
        _updateUserStakingRecord(_msgSender(), rec.staked, 0);

        emit LOG_CLAIM_PROFIT(_msgSender(), totalProfit);

        _pushShareToken(_msgSender(), totalProfit);
    }

    function _getTotalProfit(address staker) internal returns (uint) {
        _updateUnitProfitState();

        uint totalProfit = _settleCurrentUserProfit(staker);
        return totalProfit;
    }

    function _updateUserStakingRecord(address staker, uint staked, uint totalProfit) internal {
        _stakingRecords[staker].staked = staked;
        _stakingRecords[staker].totalProfit = totalProfit;
        _stakingRecords[staker].blockTimestamp = block.timestamp;

        if (block.timestamp < startStakingBlockTimestamp) {
            _stakingRecords[staker].blockTimestamp = startStakingBlockTimestamp;
        }
    }

    function _settleCurrentUserProfit(address staker) internal view returns (uint) {
        if (block.timestamp <= startStakingBlockTimestamp) {
            return 0;
        }

        StakingRecord storage rec = _stakingRecords[staker];

        uint preUnitProfit = _unitProfitAccumu[rec.blockTimestamp];
        uint currUnitProfit = _unitProfitAccumu[block.timestamp];
        uint currentProfit = (currUnitProfit.sub(preUnitProfit)).mul(rec.staked).div(ONE);

        return rec.totalProfit.add(currentProfit);
    }

    function _updateUnitProfitState() internal {
        uint currentBlockTimestamp = block.timestamp;
        if (_upBlockTimestamp >= currentBlockTimestamp) {
            _updateUnitProfit();
            return;
        }

        // Accumulate unit profit.
        uint unitStakeProfitIncrease = _unitProfit.mul(currentBlockTimestamp.sub(_upBlockTimestamp));
        _unitProfitAccumu[currentBlockTimestamp] = unitStakeProfitIncrease.add(_unitProfitAccumu[_upBlockTimestamp]);

        _upBlockTimestamp = block.timestamp;

        if (currentBlockTimestamp <= startStakingBlockTimestamp) {
            _unitProfitAccumu[startStakingBlockTimestamp] = _unitProfitAccumu[currentBlockTimestamp];
            _upBlockTimestamp = startStakingBlockTimestamp;
        }

        _updateUnitProfit();
    }

    function _updateUnitProfit() internal {
        if (totalStaked > 0) {
            _unitProfit = _sharePerSecond.mul(ONE).div(totalStaked);
        }
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

    function rescue(address token, address to) external nonReentrant onlyOwner _logs_ {
        require(token != StakingToken, "O3Staking: RESCUE_NOT_ALLOWED");
        uint balance = IERC20(token).balanceOf(address(this));
        _pushToken(token, to, balance);
    }

    function _pushToken(address token, address to, uint amount) internal {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }

    function _pushShareToken(address to, uint amount) internal {
        IO3(O3Token).mintLockedToken(to, amount);
    }

    function _pullToken(address token, address from, uint amount) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
    }
}
