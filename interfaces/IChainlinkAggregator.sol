// SPDX-License-Identifier: MIT

pragma solidity ^0.7.4;

interface IChainlinkAggregator {
  function latestAnswer() external view returns (int256);
}