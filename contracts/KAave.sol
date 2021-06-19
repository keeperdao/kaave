// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "./Aave.sol";
import "./open_zeppelin/SafeERC20.sol";
import "./open_zeppelin/IERC20.sol";
import "./Logic.sol";
import "./helpers/Helpers.sol";


contract KAAVE {
    using SafeERC20 for IERC20;
    ILendingPool constant lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    ILendingPoolAddressesProvider constant lendingPoolAddressProvider = ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);

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
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256)  {
        // must prevent user from withdrawing buffer
        return lendingPool.withdraw(asset, amount, to);
        // validate amount remaining > buffer amount
    }

    function repay(address asset, uint256 amount, uint256 rateMode) external returns (uint256) {
        // should buffer be seized if health factor gets high enough
        return lendingPool.repay(asset, amount, rateMode, address(this));
    }

    function borrow(address asset, uint256 amount, uint256 interestRateMode) external {
        // cannot allow user to borrow against buffer
        lendingPool.borrow(asset, amount, interestRateMode, 0, address(this));
        IERC20(asset).safeApprove(address(this), amount);
        IERC20(asset).safeTransferFrom(address(this), msg.sender, amount);
    }

    function underwrite(address asset, uint256 amount) external returns (uint256) {
        // enforce some maximum health factor?
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(asset).safeApprove(address(lendingPool), amount);
        state().bufferAsset = asset;
        state().bufferAmount = amount;
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function reclaim() external {
        // can we get to a state where we can no lnoger reclaim?
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
        // will assume the interest accrued on the buffer belongs to the user
        DataTypes.ReserveData memory bufferAssetReserve = lendingPool.getReserveData(state().bufferAsset);
        DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(collateralAsset);
        DataTypes.ReserveData memory debtReserve = lendingPool.getReserveData(debtAsset);
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(address(this));
        uint256 healthFactor = Logic.calculateAdjustedHealthFactor(address(lendingPoolAddressProvider), address(this), userConfig, bufferAssetReserve, state().bufferAsset, state().bufferAmount);
        console.log('adjusted health factor', healthFactor);

        uint256 userStableDebt;
        uint256 userVariableDebt;
        (userStableDebt, userVariableDebt) = Helpers.getUserCurrentDebtMemory(address(this), debtReserve);
        console.log('user stable debt', userStableDebt);
        console.log('user variable debt', userVariableDebt);

        uint256 errorCode;
        string memory errorMsg;
        (errorCode, errorMsg) = Logic.validateLiquidationCall(
            collateralReserve,
            debtReserve,
            userConfig,
            healthFactor,
            userStableDebt,
            userVariableDebt
        );
        require(errorCode == 0, string(abi.encodePacked(errorMsg)));

        console.log('error code', errorCode);
        console.log('error mesage', errorMsg);

        uint256 actualDebtToLiquidate;
        uint256 maxCollateralToLiquidate;
        (actualDebtToLiquidate, maxCollateralToLiquidate) = calculateLiquidationAmounts(
                collateralReserve,
                debtReserve,
                collateralAsset,
                debtAsset,
                address(this),
                address(lendingPoolAddressProvider),
                userStableDebt,
                userVariableDebt,
                debtToCover
        );

    } 
}