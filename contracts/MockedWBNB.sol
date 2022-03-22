// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockedWBNB is ERC20 {
    uint256 public constant ERR_NO_ERROR = 0x0;
    uint256 public constant ERR_INVALID_ZERO_VALUE = 0x01;

    constructor() public ERC20("Wrapped Fantom", "WBNB") {}

    function mint(uint256 amount) external returns (bool) {
        _mint(msg.sender, amount);
        return true;
    }

    function deposit() public payable returns (uint256) {
        if (msg.value == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }
        _mint(msg.sender, msg.value);
        return ERR_NO_ERROR;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        if (amount == 0) {
            return ERR_INVALID_ZERO_VALUE;
        }
        _burn(msg.sender, amount);
        msg.sender.transfer(amount);
        return ERR_NO_ERROR;
    }
}
