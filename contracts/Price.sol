// SPDX-License-Identifier: MIT

pragma solidity ^0.7.4;

import {IPriceOracleGetter} from '../interfaces/IPriceOracleGetter.sol';
import {IChainlinkAggregator} from '../interfaces/IChainlinkAggregator.sol';

contract Price is IChainlinkAggregator {
    function latestAnswer() external override pure returns (int256) {
        //about 4.4$
        return 2000000000000000;
    }
}