// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "../interfaces/IERC20.sol";
import "hardhat/console.sol";
import "./Aave.sol";
import {ILendingPool} from './Aave.sol';
import {IPriceOracleGetter} from '../interfaces/IPriceOracleGetter.sol';
import {IProtocolDataProvider} from '../interfaces/IProtocolDataProvider.sol';
import {SafeMath} from "../libraries/SafeMath.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
//import {GenericLogic} from '../libraries/GenericLogic.sol'

contract KAAVE {

    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    ILendingPool constant lendingPool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IERC20 constant wethProxy = IERC20(0x541dCd3F00Bcd1A683cc73E1b2A8693b602201f4);
    
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;
    bytes32 constant KAAVE_STORAGE_POSITION = keccak256("keeperdao.hiding-vault.aave.storage");
    uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

    address public jitu;

    struct LiquidationLocalVars {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 liquidationThreshold; 
        uint256 healthFactor;
        uint256 priceBuffer;
        uint256 priceDebt;
        uint256 bufferAmountEth;
        uint256 debtToCoverEth;
        uint256 stableDebtBalance;
        uint256 variableDebtBalance;
        uint256 maxDebtToRepay;
        uint256 maxRepayableDebt;
        uint256 collateralToWithdraw;
        uint256 maxDebtToRepayETH;
        uint256 aCollateralBalance;
        uint256 aCollateralBalanceETH;
        uint256 priceACollateral;
        uint256 aCollateralToWithdraw;
        uint256 repaidAmount;
        uint256 result;
        address aTokenAddress;
        address collateralAsset;
    }


    modifier onlyJitu {
        require(msg.sender == jitu);
        _;
    }

    struct State {
        address bufferAsset;
        uint256 bufferAmount;
    }

    function setJitu(address _jitu) external {
        jitu = _jitu;
    }

    function state() internal pure returns (State storage s) {
        bytes32 position = KAAVE_STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    function deposit(address asset, uint256 amount) external {
        //personal note: first approve from caller will be done on frontend side
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        //personal note: funds are pulled from KAave contract so we approve the lendingPool to pull the contract funds
        IERC20(asset).approve(address(lendingPool), amount);
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256)  {
        return lendingPool.withdraw(asset, amount, to);
    }

    function repay(address asset, uint256 amount, uint256 rateMode) external returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(lendingPool), amount);
        return lendingPool.repay(asset, amount, rateMode, address(this));
    }

    function borrow(address asset, uint256 amount, uint256 interestRateMode) external {
        lendingPool.borrow(asset, amount, interestRateMode, 0, address(this));
    }

    function underwrite(address asset, uint256 amount) external {
        state().bufferAsset = asset;
        state().bufferAmount = amount;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(lendingPool), amount);
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
        address _collateralAsset, 
        address _debtAsset, 
        //address _user, - we assume user is the wrapped lending position which is this contract address
        uint256 _debtToCover, 
        bool _receiveAToken
    ) onlyJitu external {
        /*

        We are trying to liquidate the collateral of the user using the repay
        We want to
        1. check te underlying position totalCollateral - bufferCollateral and check if it's underwater
        2. repay with debtAsset if that is the case
        3. seize the collateral by transferring a percentage of totalCollateral - bufferCollateral
        4. checking in the end if the position is still underwater??

        */
        
        LiquidationLocalVars memory vars;
        vars.collateralAsset = _collateralAsset;

        (vars.totalCollateralETH, 
            vars.totalDebtETH, , 
            vars.liquidationThreshold,
            , 
            ) = lendingPool.getUserAccountData(address(this));

        require(vars.totalDebtETH != 0, "there is no debt");
        //return the lending pool address provider
        ILendingPoolAddressesProvider poolAddressProvider = ILendingPoolAddressesProvider(lendingPool.getAddressesProvider());

        //proxy price provider contract
        IPriceOracleGetter oracle = IPriceOracleGetter(poolAddressProvider.getPriceOracle());
        //price returned in ETH
        vars.priceBuffer = oracle.getAssetPrice(_collateralAsset);
        vars.priceDebt = oracle.getAssetPrice(_debtAsset);
        require(vars.priceBuffer != 0 && vars.priceDebt != 0, "oracle rates yield 0");

        vars.bufferAmountEth = (state().bufferAmount).wadMul(vars.priceBuffer);
        vars.debtToCoverEth = _debtToCover.wadMul(vars.priceDebt);
        require(vars.debtToCoverEth < vars.totalDebtETH, "you are trying to repay too much debt");

        //logic explained in GenericLogic.sol Aave library, function calculateHealthFactorFromBalances
        //logic to check
        vars.result = vars.totalCollateralETH.sub(vars.bufferAmountEth);
        vars.healthFactor = ((vars.result).wadDiv(vars.totalDebtETH))
            .percentMul(vars.liquidationThreshold);
        
        if(vars.healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {}
        else {
            vars.maxDebtToRepay = _debtToCover;
            vars.maxDebtToRepayETH = vars.debtToCoverEth;
            //next use protocol data provider to get stable debt and variable debt tokens
            address protocolDataProvider = poolAddressProvider  
                .getAddress(0x0100000000000000000000000000000000000000000000000000000000000000);
            IProtocolDataProvider dataProvider = IProtocolDataProvider(protocolDataProvider);

            (, address stableDebtTokenAddress, address variableDebtTokenAddress) 
                = dataProvider.getReserveTokensAddresses(_debtAsset);

            vars.stableDebtBalance = IERC20(stableDebtTokenAddress).balanceOf(address(this));
            vars.variableDebtBalance = IERC20(variableDebtTokenAddress).balanceOf(address(this));

            uint256 priceStableDebt = oracle.getAssetPrice(stableDebtTokenAddress);
            uint256 priceVariableDebt = oracle.getAssetPrice(variableDebtTokenAddress);

            //applying a repay threshold limit of 50% of the current debt (denominated in _debtAsset)
            //the maxRepayableDebt amount is given in ETH
            vars.maxRepayableDebt = (vars.stableDebtBalance.wadMul(priceStableDebt))
                .add((vars.variableDebtBalance).wadMul(priceVariableDebt))
                .percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

            if(vars.maxDebtToRepayETH > vars.maxRepayableDebt) {
                vars.maxDebtToRepayETH = vars.maxRepayableDebt;
                //denominated back into debt asset price
                vars.maxDebtToRepay = vars.maxDebtToRepayETH.wadDiv(vars.priceDebt);
            }



            IERC20(_debtAsset).transferFrom(msg.sender, address(this), _debtToCover);
            IERC20(_debtAsset).approve(address(lendingPool), _debtToCover);

            /*
            if(vars.variableDebtBalance.wadMul(priceVariableDebt) > vars.maxDebtToRepayETH) {
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay, 2, address(this));
            } else if (vars.variableDebtBalance > 0) {
                //we convert the variable debt balance into an amount denominated in the debt token we are trying to repay
                //we repay all the variable debt balance first
                uint256 variableDebtBalanceInDebtToken = (vars.variableDebtBalance.wadMul(priceVariableDebt)).wadDiv(vars.priceDebt);
                lendingPool.repay(_debtAsset, variableDebtBalanceInDebtToken, 2, address(this));
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay.sub(variableDebtBalanceInDebtToken), 1, address(this));
            } else {
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay, 1, address(this));
            }
            */
            //uint256 repaidAmount = 0;
            try
                    lendingPool.repay(_debtAsset, _debtToCover, 2, address(this))
                returns (uint256 variableRepayment) {
                    vars.repaidAmount = vars.repaidAmount.add(variableRepayment);
                } catch {}
                // If amount repaid is less than debtToCover specified, try and also pay off stable debt
                if (vars.repaidAmount < _debtToCover) {
                    try
                        lendingPool.repay(
                            _debtAsset,
                            _debtToCover.sub(vars.repaidAmount),
                            1,
                            address(this)
                        )
                    returns (uint256 stableRepayment) {
                        vars.repaidAmount = vars.repaidAmount.add(stableRepayment);
                    } catch {}
                }

            require(vars.repaidAmount > 0, "no amount repaid");
            //next is withdrawal of collateral
            vars.collateralToWithdraw = (vars.repaidAmount.wadMul(vars.priceDebt)).wadDiv(vars.priceBuffer);
            

            require(_collateralAsset == state().bufferAsset, "collateral and buffer are not the same");


            //we need the price of the collateral aToken
            (address aCollateralAsset, , ) 
            = dataProvider.getReserveTokensAddresses(vars.collateralAsset);

            //other method to retrieve aToken
            DataTypes.ReserveData memory collateralData =
                    lendingPool.getReserveData(vars.collateralAsset);
            vars.aTokenAddress = collateralData.aTokenAddress;
            console.log("address aToken is %s", vars.aTokenAddress);
            /*
                aToken seems to be pegged to the underlying token 1:1 
                anyway so using oracle and conversions for aTokens is
                actually not relevant
            */
            console.log("address aToken is %s", aCollateralAsset);
            vars.priceACollateral = oracle.getAssetPrice(vars.collateralAsset);
            vars.aCollateralToWithdraw = (vars.repaidAmount.wadMul(vars.priceDebt)).wadDiv(vars.priceACollateral);
            console.log("aCollateral to withdraw is %s", vars.aCollateralToWithdraw);
            vars.aCollateralBalance = IERC20(aCollateralAsset).balanceOf(address(this));
            console.log("aCollateral balance of vault is %s", vars.aCollateralBalance);

            require(vars.aCollateralBalance >= vars.aCollateralToWithdraw, "not enough collateral asset balance to transfer");
            vars.aCollateralBalanceETH = vars.aCollateralBalance.wadMul(vars.priceACollateral);
            require(vars.aCollateralBalanceETH > vars.maxDebtToRepayETH, "not enough collateral amount for the asset you want to withdraw");


            if(_receiveAToken) {  
                IERC20(aCollateralAsset).transfer(msg.sender, vars.aCollateralToWithdraw);
            } else {
                lendingPool.withdraw(vars.collateralAsset, vars.collateralToWithdraw, msg.sender);
            }
        }
    } 
}