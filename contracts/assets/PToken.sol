// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PToken is ERC20, Ownable {

    uint8 private _decimals;
    mapping (address => bool) private _authorizedCaller;

    modifier onlyAuthorizedCaller() {
        require(_msgSender() == owner() || _authorizedCaller[_msgSender()],"PTOKEN: NOT_AUTHORIZED");
        _;
    }

    constructor (string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyAuthorizedCaller {
        require(amount != 0, "ERC20: zero mint amount");
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyAuthorizedCaller {
        _burn(msg.sender, amount);
    }

    function setAuthorizedCaller(address caller) external onlyOwner {
        _authorizedCaller[caller] = true;
    }

    function removeAuthorizedCaller(address caller) external onlyOwner {
        _authorizedCaller[caller] = false;
    }

    function checkAuthorizedCaller(address caller) external view returns (bool) {
        return _authorizedCaller[caller];
    }
}
