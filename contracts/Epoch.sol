// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Operator.sol";

contract Epoch is Operator {
    using SafeMath for uint256;

    uint256 private period;
    uint256 private startTime;
    uint256 private lastEpochTime;
    uint256 private epoch;

    function getCurrentEpoch() public view returns (uint256) {
        return epoch;
    }

    function getLastEpochTime() public view returns (uint256) {
        return lastEpochTime;
    }

    function getPeriod() public view returns (uint256) {
        return period;
    }

    function getStartTime() public view returns (uint256) {
        return startTime;
    }

    function nextEpochPoint() public view returns (uint256) {
        return lastEpochTime.add(period);
    }

    constructor(
        uint256 _period,
        uint256 _startTime,
        uint256 _startEpoch
    ) public {
        period = _period;
        startTime = _startTime;
        epoch = _startEpoch;
        lastEpochTime = startTime.sub(period);
    }

    function setEpoch(uint256 _epoch) external onlyOperator {
        epoch = _epoch;
    }

    function setPeriod(uint256 _period) external onlyOperator {
        require(
            _period >= 1 hours && _period <= 48 hours,
            "_period: out of range"
        );
        period = _period;
    }

    modifier checkEpoch() {
        uint256 _nextEpochPoint = nextEpochPoint();
        if (now < _nextEpochPoint) {
            require(
                msg.sender == operator(),
                "Epoch: only operator allowed for pre-epoch"
            );
            _;
        } else {
            _;
            for (;;) {
                lastEpochTime = _nextEpochPoint;
                ++epoch;
                _nextEpochPoint = nextEpochPoint();
                if (now < _nextEpochPoint) break;
            }
        }
    }

    modifier checkStartTime() {
        require(now >= startTime, "Epoch: not started yet");
        _;
    }
}
