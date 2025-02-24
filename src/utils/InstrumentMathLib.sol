// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FixedPointMathLib.sol";

/**
 * @title InstrumentMath
 * @notice Library for money market instrument calculations
 */
library InstrumentMathLib {
    using FixedPointMathLib for uint256;

    uint256 constant YEAR_IN_SECONDS = 365 days;
    uint256 constant BP_SCALE = 10000; // 100% = 10000

    struct YieldParams {
        uint256 principal;
        uint256 yieldRate; // in basis points
        uint256 timeStart;
        uint256 timeEnd;
        bool isDiscounted;
    }

    /**
     * @notice Calculates yield for zero-coupon instruments
     */
    function calculateDiscountedYield(YieldParams memory params) internal pure returns (uint256) {
        uint256 duration = params.timeEnd - params.timeStart;
        uint256 yearFraction = (duration * FixedPointMathLib.SCALE) / YEAR_IN_SECONDS;

        uint256 yield = params.principal.mulDivDown(params.yieldRate, BP_SCALE);

        return yield.mulDivDown(yearFraction, FixedPointMathLib.SCALE);
    }

    /**
     * @notice Calculates yield for interest-bearing instruments
     */
    function calculateCouponYield(YieldParams memory params) internal pure returns (uint256) {
        uint256 duration = params.timeEnd - params.timeStart;
        uint256 yearFraction = (duration * FixedPointMathLib.SCALE) / YEAR_IN_SECONDS;

        uint256 annualYield = params.principal.mulDivDown(params.yieldRate, BP_SCALE);

        return annualYield.mulDivDown(yearFraction, FixedPointMathLib.SCALE);
    }
}
