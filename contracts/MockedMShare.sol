// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "./MShare.sol";

contract MockedMShare is MShare {
    constructor(
        uint256 _startTime,
        address _communityFund,
        address _devFund,
        address _treasuryFund
    ) public MShare(_startTime, _communityFund, _devFund, _treasuryFund) {}

    function mint(uint256 amount) external returns (bool) {
        _mint(msg.sender, amount);
        return true;
    }
}
