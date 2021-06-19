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

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

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

}