// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// helpful pure math functions
library Math {
    uint256 internal constant MAX_UINT256 = 2 ** 256 - 1;

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))) {
                revert(0, 0)
            }

            // Divide x * y by the denominator.
            z := div(mul(x, y), denominator)
        }
    }
}
