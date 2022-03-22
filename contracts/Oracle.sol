// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./PancakeOracleLibrary.sol";
import "./Epoch.sol";

contract Oracle is Epoch {
    using SafeMath for uint256;
    using FixedPoint for *;

    address public token0;
    address public token1;
    IPancakePair public pair;
    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    function consult(address _token, uint256 _amountIn)
        external
        view
        returns (uint144 amountOut)
    {
        if (_token == token0) {
            amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            require(_token == token1, "Oracle: INVALID_TOKEN");
            amountOut = price1Average.mul(_amountIn).decode144();
        }
    }

    function twap(address _token, uint256 _amountIn)
        external
        view
        returns (uint144 _amountOut)
    {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = PancakeOracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (_token == token0) {
            _amountOut = FixedPoint
                .uq112x112(
                    uint224(
                        (price0Cumulative - price0CumulativeLast) / timeElapsed
                    )
                )
                .mul(_amountIn)
                .decode144();
        } else if (_token == token1) {
            _amountOut = FixedPoint
                .uq112x112(
                    uint224(
                        (price1Cumulative - price1CumulativeLast) / timeElapsed
                    )
                )
                .mul(_amountIn)
                .decode144();
        }
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);

    constructor(
        IPancakePair _pair,
        uint256 _period,
        uint256 _startTime
    ) public Epoch(_period, _startTime, 0) {
        pair = _pair;
        token0 = pair.token0();
        token1 = pair.token1();
        price0CumulativeLast = pair.price0CumulativeLast();
        price1CumulativeLast = pair.price1CumulativeLast();
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES");
    }

    function update() external checkEpoch {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = PancakeOracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed == 0) {
            return;
        }
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
        emit Updated(price0Cumulative, price1Cumulative);
    }
}
