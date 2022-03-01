// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PToken is ERC20, Ownable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint8 private _decimals;
    uint8 private _underlyingTokenDecimals;
    bool private _depositWithdrawEnabled;
    address private _tokenUnderlying;
    mapping (address => bool) private _authorizedCaller;

    modifier onlyAuthorizedCaller() {
        require(_msgSender() == owner() || _authorizedCaller[_msgSender()],"PTOKEN: NOT_AUTHORIZED");
        _;
    }

    modifier onlyDepositWithdrawEnabled() {
        require(_depositWithdrawEnabled, "PTOKEN: Deposit and withdrawal not enabled");
        _;
    }

    constructor (string memory name_, string memory symbol_, address tokenUnderlying_) ERC20(name_, symbol_) {
        _decimals = 18;
        _underlyingTokenDecimals = ERC20(tokenUnderlying_).decimals();
        _tokenUnderlying = tokenUnderlying_;
        _depositWithdrawEnabled = false;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function tokenUnderlying() public view returns(address) {
        return _tokenUnderlying;
    }

    function mint(address to, uint256 amount) external onlyAuthorizedCaller {
        require(amount != 0, "ERC20: zero mint amount");
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyAuthorizedCaller {
        _burn(msg.sender, amount);
    }

    // deposit input amount is the original token amount
    // e.g. USDT decimals is 6 , pUSDT decimals is 18
    // when deposit 1$ USDT , amount is 10**6 , and you'll receive 10**18 pUSDT
    function deposit(address to, uint256 amount) external onlyDepositWithdrawEnabled {
        IERC20(_tokenUnderlying).safeTransferFrom(_msgSender(), address(this), amount);
        _mint(to, _precisionConversion(false, amount));
    }

    // withdraw input amount is the ptoken amount
    // e.g. USDT decimals is 6 , pUSDT decimals is 18
    // when withdraw 1$ pUSDT , amount is 10**18 , and you'll receive 10**6 USDT
    function withdraw(address to, uint256 amount) external onlyDepositWithdrawEnabled {
        _burn(_msgSender(), amount);
        IERC20(_tokenUnderlying).safeTransfer(to, _precisionConversion(true, amount));
    }

    function setAuthorizedCaller(address caller) external onlyOwner {
        _authorizedCaller[caller] = true;
    }

    function removeAuthorizedCaller(address caller) external onlyOwner {
        _authorizedCaller[caller] = false;
    }

    function enableDepositWithdraw() external onlyOwner {
        _depositWithdrawEnabled = true;
    }
 
    function disableDepositWithdraw() external onlyOwner {
        _depositWithdrawEnabled = false;
    }

    function checkAuthorizedCaller(address caller) external view returns (bool) {
        return _authorizedCaller[caller];
    }

    function checkIfDepositWithdrawEnabled() external view returns (bool) {
        return _depositWithdrawEnabled;
    }

    function _precisionConversion(bool fromPToken, uint256 amount) internal view returns(uint256) {
        if (fromPToken) {
            return amount.mul(10**_underlyingTokenDecimals).div(10**_decimals);
        } else {
            return amount.mul(10**_decimals).div(10**_underlyingTokenDecimals);
        }
    }
}
