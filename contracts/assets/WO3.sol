// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./interfaces/IO3.sol";
import "../access/Rescuable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WO3 is ERC20, IO3, ReentrancyGuard, Rescuable {
    using SafeERC20 for IERC20;

    struct LpStakeInfo {
        uint256 amountStaked;
        uint256 blockNumber;
    }

    event LOG_UNLOCK_TRANSFER (
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event LOG_STAKE (
        address indexed staker,
        address indexed token,
        uint256 stakeAmount
    );

    event LOG_UNSTAKE (
        address indexed staker,
        address indexed token,
        uint256 unstakeAmount
    );

    event LOG_CLAIM_UNLOCKED (
        address indexed staker,
        uint256 claimedAmount
    );

    event LOG_SET_UNLOCK_FACTOR (
        address indexed token,
        uint256 factor
    );

    event LOG_SET_UNLOCK_BLOCK_GAP (
        address indexed token,
        uint256 blockGap
    );

    uint256 public constant FACTOR_DENOMINATOR = 10 ** 8;

    mapping (address => uint256) private _unlocks;
    mapping (address => mapping(address => LpStakeInfo)) private _stakingRecords;
    mapping (address => uint256) private _unlockFactor;
    mapping (address => uint256) private _unlockBlockGap;
    mapping (address => bool) private _authorizedMintCaller;

    uint256 private _totalUnlocked;

    modifier onlyAuthorizedMintCaller() {
        require(_msgSender() == owner() || _authorizedMintCaller[_msgSender()], "WO3: MINT_CALLER_NOT_AUTHORIZED");
        _;
    }

    constructor () ERC20("O3 Swap Token", "WO3") {}

    function getUnlockFactor(address token) external view override returns (uint256) {
        return _unlockFactor[token];
    }

    function getUnlockBlockGap(address token) external view override returns (uint256) {
        return _unlockBlockGap[token];
    }

    function totalUnlocked() external view override returns (uint256) {
        return _totalUnlocked;
    }

    function unlockedOf(address account) external view override returns (uint256) {
        return _unlocks[account];
    }

    function lockedOf(address account) public view override returns (uint256) {
        return balanceOf(account) - _unlocks[account];
    }

    function getStaked(address token) external view override returns (uint256) {
        return _stakingRecords[_msgSender()][token].amountStaked;
    }

    function getUnlockSpeed(address staker, address token) external view override returns (uint256) {
        LpStakeInfo storage info = _stakingRecords[staker][token];
        return _getUnlockSpeed(token, staker, info.amountStaked);
    }

    function claimableUnlocked(address token) external view override returns (uint256) {
        LpStakeInfo storage info = _stakingRecords[_msgSender()][token];
        return _settleUnlockAmount(_msgSender(), token, info.amountStaked, info.blockNumber);
    }

    function transfer(address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        _unlockTransfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override(ERC20, IERC20) returns (bool) {
        _spendAllowance(sender, _msgSender(), amount);
        _transfer(sender, recipient, amount);
        _unlockTransfer(sender, recipient, amount);
        return true;
    }

    function setUnlockFactor(address token, uint256 _factor) external override onlyOwner {
        _unlockFactor[token] = _factor;
        emit LOG_SET_UNLOCK_FACTOR(token, _factor);
    }

    function setUnlockBlockGap(address token, uint256 _blockGap) external override onlyOwner {
        _unlockBlockGap[token] = _blockGap;
        emit LOG_SET_UNLOCK_BLOCK_GAP(token, _blockGap);
    }

    function stake(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(_unlockFactor[token] > 0, "WO3: FACTOR_NOT_SET");
        require(_unlockBlockGap[token] > 0, "WO3: BLOCK_GAP_NOT_SET");
        _pullToken(token, _msgSender(), amount);
        LpStakeInfo storage info = _stakingRecords[_msgSender()][token];
        uint256 unlockedAmount = _settleUnlockAmount(_msgSender(), token, info.amountStaked, info.blockNumber);
        _updateStakeRecord(_msgSender(), token, info.amountStaked + amount);
        _mintUnlocked(_msgSender(), unlockedAmount);
        emit LOG_STAKE(_msgSender(), token, amount);
        return true;
    }

    function unstake(address token, uint256 amount) external override nonReentrant returns (bool) {
        require(amount > 0, "WO3: ZERO_UNSTAKE_AMOUNT");
        LpStakeInfo storage info = _stakingRecords[_msgSender()][token];
        require(amount <= info.amountStaked, "WO3: UNSTAKE_AMOUNT_EXCEEDED");
        uint256 unlockedAmount = _settleUnlockAmount(_msgSender(), token, info.amountStaked, info.blockNumber);
        _updateStakeRecord(_msgSender(), token, info.amountStaked - amount);
        _mintUnlocked(_msgSender(), unlockedAmount);
        _pushToken(token, _msgSender(), amount);
        emit LOG_UNSTAKE(_msgSender(), token, amount);
        return true;
    }

    function claimUnlocked(address token) external override nonReentrant returns (bool) {
        LpStakeInfo storage info = _stakingRecords[_msgSender()][token];
        uint256 unlockedAmount = _settleUnlockAmount(_msgSender(), token, info.amountStaked, info.blockNumber);
        _updateStakeRecord(_msgSender(), token, info.amountStaked);
        _mintUnlocked(_msgSender(), unlockedAmount);
        emit LOG_CLAIM_UNLOCKED(_msgSender(), unlockedAmount);
        return true;
    }

    function _updateStakeRecord(address staker, address token, uint256 _amountStaked) internal {
        _stakingRecords[staker][token].amountStaked = _amountStaked;
        _stakingRecords[staker][token].blockNumber = block.number;
    }

    function mintUnlockedToken(address to, uint256 amount) onlyAuthorizedMintCaller external override {
        _mint(to, amount);
        _mintUnlocked(to, amount);
        require(totalSupply() <= 10**26, "WO3: TOTAL_SUPPLY_EXCEEDED");
    }

    function mintLockedToken(address to, uint256 amount) onlyAuthorizedMintCaller external override {
        _mint(to, amount);
        require(totalSupply() <= 10**26, "WO3: TOTAL_SUPPLY_EXCEEDED");
    }

    function setAuthorizedMintCaller(address caller) onlyOwner external override {
        _authorizedMintCaller[caller] = true;
    }

    function removeAuthorizedMintCaller(address caller) onlyOwner external override {
        _authorizedMintCaller[caller] = false;
    }

    function _settleUnlockAmount(address staker, address token, uint256 lpStaked, uint256 upToBlockNumber) internal view returns (uint256) {
        uint256 unlockSpeed = _getUnlockSpeed(token, staker, lpStaked);
        uint256 blocks = block.number - upToBlockNumber;
        uint256 unlockedAmount = unlockSpeed * blocks / FACTOR_DENOMINATOR;
        uint256 lockedAmount = lockedOf(staker);
        if (unlockedAmount > lockedAmount) {
            unlockedAmount = lockedAmount;
        }
        return unlockedAmount;
    }

    function _mintUnlocked(address recipient, uint256 amount) internal {
        _unlocks[recipient] = _unlocks[recipient] + amount;
        _totalUnlocked = _totalUnlocked + amount;
        emit LOG_UNLOCK_TRANSFER(address(0), recipient, amount);
    }

    function _getUnlockSpeed(address token, address staker, uint256 lpStaked) internal view returns (uint256) {
        uint256 toBeUnlocked = lockedOf(staker);
        uint256 unlockSpeed = _unlockFactor[token] * lpStaked;
        uint256 maxUnlockSpeed = toBeUnlocked * FACTOR_DENOMINATOR / _unlockBlockGap[token];
        if(unlockSpeed > maxUnlockSpeed) {
            unlockSpeed = maxUnlockSpeed;
        }
        return unlockSpeed;
    }

    function _unlockTransfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        _unlocks[sender] = _unlocks[sender] - amount;
        _unlocks[recipient] = _unlocks[recipient] + amount;
        emit LOG_UNLOCK_TRANSFER(sender, recipient, amount);
    }

    function _pullToken(address token, address from, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    function _pushToken(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }
}
