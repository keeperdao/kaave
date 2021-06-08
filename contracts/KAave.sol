// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;

import "hardhat/console.sol";
import "./AAVE.sol";

contract KAAVE {
    ILendingPool constant lendingPool = ILendingPool(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    bytes32 constant KAAVE_STORAGE_POSITION = keccak256("keeperdao.hiding-vault.aave.storage");

    struct State {
        address bufferAsset;
        uint256 bufferAmount;
    }

    function state() internal pure returns (State storage s) {
        bytes32 position = KAAVE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function deposit(address asset, uint256 amount) external {
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256)  {
        return lendingPool.withdraw(asset, amount, to);
    }

    function repay(address asset, uint256 amount, uint256 rateMode) external returns (uint256) {
        return lendingPool.repay(asset, amount, rateMode, address(this));
    }

    function borrow(address asset, uint256 amount, uint256 interestRateMode) external {
        lendingPool.borrow(asset, amount, interestRateMode, 0, address(this));
    }

    function underwrite(address asset, uint256 amount) external returns (uint256) {
        state().bufferAsset = asset;
        state().bufferAmount = amount;
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function reclaim() external {
        lendingPool.withdraw(
            state().bufferAsset,
            state().bufferAmount, 
            msg.sender
        );
    }

    function preempt(
        address collateralAsset, 
        address debtAsset, 
        address user, 
        uint256 debtToCover, 
        bool receiveAToken
    ) external {
        // TODO: Implement This
        // TODO: this function should simulate liquidationCall on AAVE but by not considering
        //       the buffer provided as collateral in the calculations to check if a position
        //       is underwater.
    } 
}