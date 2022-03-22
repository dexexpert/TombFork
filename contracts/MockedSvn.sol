// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./Svn.sol";

contract MockedSvn is SavannaToken {
    constructor(uint256 _taxRate, address _taxCollectorAddress)
        public
        SavannaToken(_taxRate, _taxCollectorAddress)
    {}

    function mint(uint256 amount) external returns (bool) {
        _mint(msg.sender, amount);
        return true;
    }
}
