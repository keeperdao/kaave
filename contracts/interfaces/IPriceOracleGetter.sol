// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;

interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
}
