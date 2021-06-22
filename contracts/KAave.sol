// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.4;

import "../interfaces/IERC20.sol";
import "hardhat/console.sol";
import "./Aave.sol";
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

    ILendingPool constant lendingPool = ILendingPool(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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

        (vars.totalCollateralETH, 
            vars.totalDebtETH, , 
            vars.liquidationThreshold,
            , 
            ) = lendingPool.getUserAccountData(address(this));

        //return the lending pool address provider
        ILendingPoolAddressesProvider poolAddressProvider = ILendingPoolAddressesProvider(lendingPool.getAddressesProvider());

        //proxy price provider contract
        IPriceOracleGetter oracle = IPriceOracleGetter(poolAddressProvider.getPriceOracle());
        //price returned in ETH
        vars.priceBuffer = oracle.getAssetPrice(state().bufferAsset);
        vars.priceDebt = oracle.getAssetPrice(_debtAsset);

        vars.bufferAmountEth = (state().bufferAmount).mul(vars.priceBuffer);
        vars.debtToCoverEth = _debtToCover.mul(vars.priceDebt);
        require(vars.debtToCoverEth < vars.totalDebtETH, "you are trying to repay too much debt");

        //logic explained in GenericLogic.sol Aave library, function calculateHealthFactorFromBalances
        //REVIEW
        vars.healthFactor = (vars.totalCollateralETH.sub(vars.bufferAmountEth))
            .percentMul(vars.liquidationThreshold)
            .wadDiv(vars.totalDebtETH);
        
        if(vars.healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {}
        else {
            vars.maxDebtToRepay = _debtToCover;
            vars.maxDebtToRepayETH = debtToCoverEth;
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
            vars.maxRepayableDebt = (vars.stableDebtBalance.mul(priceStableDebt))
                .add((vars.variableDebtBalance).mul(priceVariableDebt))
                .percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

            //REVIEW-not good here since I am comparing the debt asset with the balances of underlying debt tokens
            if(vars.maxDebtToRepayETH > vars.maxRepayableDebt) {
                vars.maxDebtToRepayETH = vars.maxRepayableDebt;
                //denominated back into debt asset price
                vars.maxDebtToRepay = vars.maxDebtToRepayETH.div(vars.priceDebt);
            }



            IERC20(_debtAsset).transferFrom(msg.sender, address(this), vars.maxDebtToRepay);
            IERC20(_debtAsset).approve(address(lendingPool), vars.maxDebtToRepay);

            if(vars.variableDebtBalance.mul(priceVariableDebt) > vars.maxDebtToRepayETH) {
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay, 2, address(this));
            } else if (vars.variableDebtBalance > 0) {
                //we convert the variable debt balance into an amount denominated in the debt token we are trying to repay
                //we repay all the variable debt balance first
                uint256 variableDebtBalanceInDebtToken = (vars.variableDebtBalance.mul(priceVariableDebt)).div(vars.priceDebt);
                lendingPool.repay(_debtAsset, variableDebtBalanceInDebtToken, 2, address(this));
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay.sub(variableDebtBalanceInDebtToken), 1, address(this));
            } else {
                lendingPool.repay(_debtAsset, vars.maxDebtToRepay, 1, address(this));
            }

            //next is withdrawal of collateral
            vars.collateralToWithdraw = (vars.maxDebtToRepay.mul(vars.priceDebt)).div(vars.priceBuffer);
            require(_collateralAsset == state().bufferAsset, "collateral and buffer are not the same");

            if(_receiveAToken) {
                //we need the price of the collateral aToken
                (address aCollateralAsset, , ) 
                = dataProvider.getReserveTokensAddresses(_collateralAsset);
                uint256 priceACollateral = oracle.getAssetPrice(aCollateralAsset);
                uint256 aCollateralToWithdraw = (vars.maxDebtToRepay.mul(vars.priceDebt)).div(priceACollateral);
                IERC20(aCollateralAsset).transfer(msg.sender, aCollateralToWithdraw);
            } else {
                lendingPool.withdraw(_collateralAsset, vars.collateralToWithdraw, msg.sender);
            }
        }
    } 
}