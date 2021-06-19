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
 * @title AdjustedLogic library
 * @author egg
 * @title Implements logic to calculate and validate the state of a user adjusted by the Kaave buffer
 */
library AdjustedLogic {

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
        uint256 bufferAssetDecimals;
        uint256 bufferAssetLiquidationThreshold;
        uint256 unadjustedHealthFactor;
        uint256 unadjustedTotalCollateralETH;
        uint256 adjustedTotalCollateralETH;
        uint256 totalDebtETH;
        uint256 unadjustedAvgLiquidationThreshold;
        uint256 adjustedAvgLiquidationThreshold;
    }

    function calculateAdjustedAccountData(
        address lendingPoolAddressProvider,
        address user,
        DataTypes.UserConfigurationMap memory userConfig,
        DataTypes.ReserveData memory bufferAssetReserve,
        address bufferAsset,
        uint256 bufferAmount
    ) internal view returns (uint256, uint256, uint256, uint256) 
    {

        if (userConfig.isEmpty()) {
            return (0, 0, 0, uint256(-1));
        }
        CalculateUserAccountDataVars memory vars;
        
        ILendingPoolAddressesProvider addressProvider = ILendingPoolAddressesProvider(lendingPoolAddressProvider);
        ILendingPool lendingPool = ILendingPool(addressProvider.getLendingPool());

        (vars.unadjustedTotalCollateralETH, vars.totalDebtETH, , vars.unadjustedAvgLiquidationThreshold, , vars.unadjustedHealthFactor) = lendingPool.getUserAccountData(user);

        if (bufferAmount == 0) {
            return (
                vars.unadjustedTotalCollateralETH,
                vars.totalDebtETH,
                vars.unadjustedAvgLiquidationThreshold,
                vars.unadjustedHealthFactor
            );
        }

        (, vars.bufferAssetLiquidationThreshold, , vars.bufferAssetDecimals, ) = bufferAssetReserve.configuration.getParams();
        vars.bufferAssetUnit = 10**vars.bufferAssetDecimals;
        vars.bufferAssetUnitPrice = IPriceOracleGetter(addressProvider.getPriceOracle()).getAssetPrice(bufferAsset);

        // adjust user account data by the kaave buffer
        // retreving the account data from Aave LendingPool and subtracting buffer amounts as we do here
        // seemed the cleanest way to do it at first. in retrospect, I may have chosen to do it differently
        // knowing now that this way is vulnerable to rounding errors that could result in slight deviations
        // from expected health factor
        if (vars.bufferAssetLiquidationThreshold != 0) {
            // we will probably get extremely minor deviations from aave lendingpool health factor
            // due to rounding errors in this calculation. will not address for this challenge.
            uint256 bufferBalanceETH =
                vars.bufferAssetUnitPrice.mul(bufferAmount).div(vars.bufferAssetUnit);

            // what if buffer > user collateral?
            vars.adjustedTotalCollateralETH = vars.unadjustedTotalCollateralETH.sub(bufferBalanceETH);


            // potential for rounding error here as well
            vars.adjustedAvgLiquidationThreshold = vars.unadjustedAvgLiquidationThreshold.mul(vars.unadjustedTotalCollateralETH)
                .sub(bufferBalanceETH.mul(vars.bufferAssetLiquidationThreshold)).div(vars.adjustedTotalCollateralETH);
        }


        return (
            vars.adjustedTotalCollateralETH,
            vars.totalDebtETH,
            vars.adjustedAvgLiquidationThreshold,
            calculateHealthFactorFromBalances(vars.adjustedTotalCollateralETH, vars.totalDebtETH, vars.adjustedAvgLiquidationThreshold)
        );

    }
    
        /**
    * @dev Calculates the health factor from the corresponding balances
    * @param totalCollateralInETH The total collateral in ETH
    * @param totalDebtInETH The total debt in ETH
    * @param liquidationThreshold The avg liquidation threshold
    * @return The health factor calculated from the balances provided
    **/
    function calculateHealthFactorFromBalances( // copied from Aave contracts
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
    function validateLiquidationCall( // copied from Aave contracts
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
        // do we need to adjust these calculations by buffer size if buffer asset == collateral asset?

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
  function _calculateAvailableCollateralToLiquidate( // copied from Aave contracts
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
