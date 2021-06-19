// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;



import {IPriceOracleGetter} from './IPriceOracleGetter.sol';
import './open_zeppelin/SafeMath.sol';
import "hardhat/console.sol";


contract DiscountedPriceOracle is IPriceOracleGetter {
  IPriceOracleGetter private _sourceOracle;
  using SafeMath for uint256;


  /// @notice Constructor
  /// @param sourceOracle source oracle
  constructor(address sourceOracle) public {
    _sourceOracle = IPriceOracleGetter(sourceOracle);
  }

  /// @notice Gets an asset price by address
  /// @param asset The asset address
  function getAssetPrice(address asset) public override view returns (uint256) {
    uint256 price = _sourceOracle.getAssetPrice(asset);
    console.log('source oracle reported price', price);
    console.log('discounted price', price.div(2));
    return price.div(2);
  }

}
