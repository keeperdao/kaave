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
        // consider the scenario where a user withdraws as much against his position as he can
        // the underwriting would get triggered and he could immediately pay back to take the buffer as well
        return lendingPool.withdraw(asset, amount, to);
        // validate amount remaining > buffer amount
    }

    function repay(address asset, uint256 amount, uint256 rateMode) external returns (uint256) {
        // should buffer be seized if health factor gets high enough?
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

    struct PreemptLocalVars {
        uint256 healthFactor;
        uint256 userStableDebt;
        uint256 userVariableDebt;
        uint256 actualDebtToLiquidate;
        uint256 maxCollateralToLiquidate;
        uint256 variableDebtRepaymentAmount;
        uint256 errorCode;
        string errorMsg;
    }

    function preempt(
        address collateralAsset, 
        address debtAsset, 
        address user, 
        uint256 debtToCover, 
        bool receiveAToken
    ) external {

        // will assume the interest accrued on the buffer belongs to the user
        // what if position including the buffer is unhealthy?

        PreemptLocalVars memory vars;
        DataTypes.ReserveData memory bufferAssetReserve = lendingPool.getReserveData(state().bufferAsset);
        DataTypes.ReserveData memory collateralReserve = lendingPool.getReserveData(collateralAsset);
        DataTypes.ReserveData memory debtReserve = lendingPool.getReserveData(debtAsset);
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(address(this));
        (,,,vars.healthFactor) = Logic.calculateAdjustedAccountData(
            address(lendingPoolAddressProvider), 
            address(this), 
            userConfig, 
            bufferAssetReserve, 
            state().bufferAsset, 
            state().bufferAmount
        );
        console.log('adjusted health factor', vars.healthFactor);

        
        (vars.userStableDebt, vars.userVariableDebt) = Helpers.getUserCurrentDebtMemory(address(this), debtReserve);
        console.log('user stable debt', vars.userStableDebt);
        console.log('user variable debt', vars.userVariableDebt);

        (vars.errorCode, vars.errorMsg) = Logic.validateLiquidationCall(
            collateralReserve,
            debtReserve,
            userConfig,
            vars.healthFactor,
            vars.userStableDebt,
            vars.userVariableDebt
        );
        require(vars.errorCode == 0, string(abi.encodePacked(vars.errorMsg)));

        console.log('error code', vars.errorCode);
        console.log('error mesage', vars.errorMsg);


        (vars.actualDebtToLiquidate, vars.maxCollateralToLiquidate) = Logic.calculateLiquidationAmounts(
                collateralReserve,
                debtReserve,
                collateralAsset,
                debtAsset,
                address(this),
                address(lendingPoolAddressProvider),
                vars.userStableDebt,
                vars.userVariableDebt,
                debtToCover
        );

        console.log('debt to cover', debtToCover);
        console.log('actual debt to liquidate', vars.actualDebtToLiquidate);
        console.log('max collateral to liquidate', vars.maxCollateralToLiquidate);

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), vars.actualDebtToLiquidate);
        IERC20(debtAsset).safeApprove(address(lendingPool), vars.actualDebtToLiquidate);

        // the user's debt could be spread across variable and stable debt. 
        // arbitrarily choose variable debt to repay first for this exercise
        // should probaby choose the more commonly used debt type in practice to potentially save on a contract call and gas
        if (vars.userVariableDebt > 0) {
            vars.variableDebtRepaymentAmount = vars.actualDebtToLiquidate < vars.userVariableDebt 
                ? vars.actualDebtToLiquidate : vars.userVariableDebt;
            lendingPool.repay(debtAsset, vars.variableDebtRepaymentAmount, 2, address(this));
            vars.actualDebtToLiquidate -= vars.variableDebtRepaymentAmount;
        }
        if (vars.actualDebtToLiquidate > 0) {
            lendingPool.repay(debtAsset, vars.actualDebtToLiquidate, 1, address(this));
        }

        if (receiveAToken) {
            IERC20(collateralReserve.aTokenAddress).safeTransfer(user, vars.maxCollateralToLiquidate);
        } else {
            lendingPool.withdraw(collateralAsset, vars.maxCollateralToLiquidate, user);
        }


        // check to prevent withdrawal of buffer?

    } 

        /**
    * @dev Returns the user account data across all the reserves
    * @param user The address of the user
    * @return totalCollateralETH the total collateral in ETH of the user
    * @return totalDebtETH the total debt in ETH of the user
    * @return currentLiquidationThreshold the liquidation threshold of the user
    * @return healthFactor the current health factor of the user
    **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor
        )
    {
        DataTypes.ReserveData memory bufferAssetReserve = lendingPool.getReserveData(state().bufferAsset);
        DataTypes.UserConfigurationMap memory userConfig = lendingPool.getUserConfiguration(address(this));
        (
            totalCollateralETH,
            totalDebtETH,
            currentLiquidationThreshold,
            healthFactor
        ) = Logic.calculateAdjustedAccountData(
            address(lendingPoolAddressProvider), 
            address(this), 
            userConfig, 
            bufferAssetReserve, 
            state().bufferAsset, 
            state().bufferAmount
        );
    }
}