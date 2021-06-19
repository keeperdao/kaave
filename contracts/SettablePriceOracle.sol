// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;



import {IPriceOracleGetter} from './IPriceOracleGetter.sol';
import './open_zeppelin/SafeMath.sol';
import "hardhat/console.sol";


contract SettablePriceOracle is IPriceOracleGetter {
  uint256 private _price;
  using SafeMath for uint256;

  function setPrice(uint256 price) public {
    _price = price;
  }

  /// @notice Gets an asset price by address
  /// @param asset The asset address
  function getAssetPrice(address asset) public override view returns (uint256) {
    return _price;
  }

}
