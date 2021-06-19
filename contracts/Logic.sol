pragma solidity 0.7.4;

import "./Aave.sol";
import "hardhat/console.sol";
import "./IPriceOracleGetter.sol";
import "./open_zeppelin/IERC20.sol";
import "./open_zeppelin/SafeMath.sol";
import {WadRayMath} from './math/WadRayMath.sol';
import {PercentageMath} from './math/PercentageMath.sol';
import {ReserveConfiguration} from './configuration/ReserveConfiguration.sol';
import {UserConfiguration} from './configuration/UserConfiguration.sol';
import "./helpers/Errors.sol";
import "./IAToken.sol";




/**
 * @title Logic library
 * @author egg
 * @title Implements logic to calculate and validate the state of a user adjusted by the KCompound buffer
 */
library Logic {

    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 internal constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;
    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    struct CalculateUserAccountDataVars {
        uint256 bufferAssetUnitPrice;
        uint256 bufferAssetUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 bufferAssetDecimals;
        uint256 ltv;
        uint256 bufferAssetLiquidationThreshold;
        uint256 i;
        uint256 avgLtv;
        uint256 reservesLength;
        bool healthFactorBelowThreshold;
        address currentReserveAddress;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
        uint256 unadjustedHealthFactor;
        uint256 unadjustedTotalCollateralETH;
        uint256 adjustedTotalCollateralETH;
        uint256 totalDebtETH;
        uint256 unadjustedAvgLiquidationThreshold;
        uint256 adjustedAvgLiquidationThreshold;
    }

    function calculateAdjustedHealthFactor(
        address lendingPoolAddressProvider,
        address user,
        DataTypes.UserConfigurationMap memory userConfig,
        DataTypes.ReserveData memory bufferAssetReserve,
        address bufferAsset,
        uint256 bufferAmount
    ) internal view returns (uint256) 
    {
        console.log(bufferAsset);
        console.log(bufferAmount);

        if (userConfig.isEmpty()) {
            return uint256(-1);
        }
        CalculateUserAccountDataVars memory vars;
        
        ILendingPoolAddressesProvider addressProvider = ILendingPoolAddressesProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());

        (vars.unadjustedTotalCollateralETH, vars.totalDebtETH, , vars.unadjustedAvgLiquidationThreshold, , vars.unadjustedHealthFactor) = lendingPool.getUserAccountData(user);
        console.log('unadjusted total collateral',vars.unadjustedTotalCollateralETH);
        console.log('total debt', vars.totalDebtETH);
        console.log('unadjusted liquidationthreshold', vars.unadjustedAvgLiquidationThreshold);
        console.log('unadjusted health factor',vars.unadjustedHealthFactor);

        if (bufferAmount == 0) {
            return vars.unadjustedHealthFactor;
        }


        console.log('non-zero buffer');
        (, vars.bufferAssetLiquidationThreshold, , vars.bufferAssetDecimals, ) = bufferAssetReserve.configuration.getParams();
        console.log('liquidation threshold', vars.bufferAssetLiquidationThreshold);
        console.log('buffer asset decimals', vars.bufferAssetDecimals);
        vars.bufferAssetUnit = 10**vars.bufferAssetDecimals;
        vars.bufferAssetUnitPrice = IPriceOracleGetter(addressProvider.getPriceOracle()).getAssetPrice(bufferAsset);
        console.log('buffer asset unit', vars.bufferAssetUnit);
        console.log('buffer asset unit price', vars.bufferAssetUnitPrice);

        if (vars.bufferAssetLiquidationThreshold != 0) {
            uint256 bufferBalanceETH =
                vars.bufferAssetUnitPrice.mul(bufferAmount).div(vars.bufferAssetUnit);
            console.log('buffer balance', bufferBalanceETH);

            // what if buffer > user collateral?
            vars.adjustedTotalCollateralETH = vars.unadjustedTotalCollateralETH.sub(bufferBalanceETH);

            console.log('adjusted total collaterl', vars.adjustedTotalCollateralETH);
            vars.adjustedAvgLiquidationThreshold = vars.unadjustedAvgLiquidationThreshold.mul(vars.unadjustedTotalCollateralETH)
                .sub(bufferBalanceETH.mul(vars.bufferAssetLiquidationThreshold)).div(vars.adjustedTotalCollateralETH);
            console.log('adjusted liquiadtion threshold', vars.adjustedAvgLiquidationThreshold);
        }


        return calculateHealthFactorFromBalances(vars.adjustedTotalCollateralETH, vars.totalDebtETH, vars.adjustedAvgLiquidationThreshold);


    }

        /**
    * @dev Calculates the health factor from the corresponding balances
    * @param totalCollateralInETH The total collateral in ETH
    * @param totalDebtInETH The total debt in ETH
    * @param liquidationThreshold The avg liquidation threshold
    * @return The health factor calculated from the balances provided
    **/
    function calculateHealthFactorFromBalances(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (totalDebtInETH == 0) return uint256(-1);

        return (totalCollateralInETH.percentMul(liquidationThreshold)).wadDiv(totalDebtInETH);
    }

        /**
    * @dev Validates the liquidation action
    * @param collateralReserve The reserve data of the collateral
    * @param principalReserve The reserve data of the principal
    * @param userConfig The user configuration
    * @param userHealthFactor The user's health factor
    * @param userStableDebt Total stable debt balance of the user
    * @param userVariableDebt Total variable debt balance of the user
    **/
    function validateLiquidationCall(
        DataTypes.ReserveData memory collateralReserve,
        DataTypes.ReserveData memory principalReserve,
        DataTypes.UserConfigurationMap memory userConfig,
        uint256 userHealthFactor,
        uint256 userStableDebt,
        uint256 userVariableDebt
    ) internal view returns (uint256, string memory) {
        if (
            !collateralReserve.configuration.getActive() || !principalReserve.configuration.getActive()
        ) {
        return (
            uint256(Errors.CollateralManagerErrors.NO_ACTIVE_RESERVE),
            Errors.VL_NO_ACTIVE_RESERVE
        );
        }

        if (userHealthFactor >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            return (
                uint256(Errors.CollateralManagerErrors.HEALTH_FACTOR_ABOVE_THRESHOLD),
                Errors.LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD
            );
        }

        bool isCollateralEnabled =
        collateralReserve.configuration.getLiquidationThreshold() > 0 &&
            userConfig.isUsingAsCollateral(collateralReserve.id);

        //if collateral isn't enabled as collateral by user, it cannot be liquidated
        if (!isCollateralEnabled) {
        return (
            uint256(Errors.CollateralManagerErrors.COLLATERAL_CANNOT_BE_LIQUIDATED),
            Errors.LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED
        );
        }

        if (userStableDebt == 0 && userVariableDebt == 0) {
        return (
            uint256(Errors.CollateralManagerErrors.CURRRENCY_NOT_BORROWED),
            Errors.LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER
        );
        }

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

    struct CalculateLiquidationAmountsVariables {
        uint256 userCollateralBalance;
        uint256 maxLiquidatableDebt;
        uint256 actualDebtToLiquidate;
        uint256 maxCollateralToLiquidate;
        uint256 debtAmountNeeded;
        IAToken collateralAtoken;

    }

    function calculateLiquidationAmounts(
        DataTypes.ReserveData memory collateralReserve,
        DataTypes.ReserveData memory debtReserve,
        address collateralAsset,
        address debtAsset,
        address user,
        address lendingPoolAddressProvider,
        uint256 userStableDebt,
        uint256 userVariableDebt,
        uint256 debtToCover

    ) internal view returns (uint256, uint256) {
        // perform adjustments to account for buffer. do we need to?

        CalculateLiquidationAmountsVariables memory vars;

        vars.collateralAtoken = IAToken(collateralReserve.aTokenAddress);

        vars.userCollateralBalance = vars.collateralAtoken.balanceOf(user);

        vars.maxLiquidatableDebt = userStableDebt.add(userVariableDebt).percentMul(
            LIQUIDATION_CLOSE_FACTOR_PERCENT
        );

        vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt
            ? vars.maxLiquidatableDebt
            : debtToCover;

        (vars.maxCollateralToLiquidate, vars.debtAmountNeeded) = _calculateAvailableCollateralToLiquidate(
            collateralReserve,
            debtReserve,
            collateralAsset,
            debtAsset,
            lendingPoolAddressProvider,
            vars.actualDebtToLiquidate,
            vars.userCollateralBalance
        );

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough
        // collateral to cover the actual amount that is being liquidated, hence we liquidate
        // a smaller amount

        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        return (vars.actualDebtToLiquidate, vars.maxCollateralToLiquidate);
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 userCompoundedBorrowBalance;
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 debtAssetPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 debtAssetDecimals;
        uint256 collateralDecimals;
    }

    /**
   * @dev Calculates how much of a specific collateral can be liquidated, given
   * a certain amount of debt asset.
   * - This function needs to be called after all the checks to validate the liquidation have been performed,
   *   otherwise it might fail.
   * @param collateralReserve The data of the collateral reserve
   * @param debtReserve The data of the debt reserve
   * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
   * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
   * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
   * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
   * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints
   *                           (user balance, close factor)
   *         debtAmountNeeded: The amount to repay with the liquidation
   **/
  function _calculateAvailableCollateralToLiquidate(
    DataTypes.ReserveData memory collateralReserve,
    DataTypes.ReserveData memory debtReserve,
    address collateralAsset,
    address debtAsset,
    address lendingPoolAddressProvider,
    uint256 debtToCover,
    uint256 userCollateralBalance
  ) internal view returns (uint256, uint256) {
    uint256 collateralAmount = 0;
    uint256 debtAmountNeeded = 0;
    ILendingPoolAddressesProvider addressProvider = ILendingPoolAddressesProvider(lendingPoolAddressProvider);
    IPriceOracleGetter oracle = IPriceOracleGetter(addressProvider.getPriceOracle());

    AvailableCollateralToLiquidateLocalVars memory vars;

    vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
    vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

    (, , vars.liquidationBonus, vars.collateralDecimals, ) = collateralReserve
      .configuration
      .getParams();
    vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

    // This is the maximum possible amount of the selected collateral that can be liquidated, given the
    // max amount of liquidatable debt
    vars.maxAmountCollateralToLiquidate = vars
      .debtAssetPrice
      .mul(debtToCover)
      .mul(10**vars.collateralDecimals)
      .percentMul(vars.liquidationBonus)
      .div(vars.collateralPrice.mul(10**vars.debtAssetDecimals));

    if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
      collateralAmount = userCollateralBalance;
      debtAmountNeeded = vars
        .collateralPrice
        .mul(collateralAmount)
        .mul(10**vars.debtAssetDecimals)
        .div(vars.debtAssetPrice.mul(10**vars.collateralDecimals))
        .percentDiv(vars.liquidationBonus);
    } else {
      collateralAmount = vars.maxAmountCollateralToLiquidate;
      debtAmountNeeded = debtToCover;
    }
    return (collateralAmount, debtAmountNeeded);
  }

}
