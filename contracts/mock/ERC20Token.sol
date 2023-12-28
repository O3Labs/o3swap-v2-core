// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "../access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Token is ERC20, Ownable {
    uint8 private immutable _decimals;
    mapping(address => bool) public authCallers;

    modifier onlyCallers() {
        require(authCallers[msg.sender] || msg.sender == owner(), "caller not authorized");
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function setAuthorizedCaller(address _caller) external onlyOwner {
        authCallers[_caller] = true;
    }

    function mint(address to, uint256 amount) external onlyCallers {
        _mint(to, amount);
    }
}
