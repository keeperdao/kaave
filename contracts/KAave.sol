// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "./Aave.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IPriceOracleGetter} from "./interfaces/IPriceOracleGetter.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {WadRayMath} from "./libraries/WadRayMath.sol";
import {PercentageMath} from "./libraries/PercentageMath.sol";

contract KAAVE {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    uint256 constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    ILendingPool constant lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    bytes32 constant KAAVE_STORAGE_POSITION =
        keccak256("keeperdao.hiding-vault.aave.storage");

    // If this is meant to be called from a stored state stored in an NFT
    // Probably would have to make all these functions ownable by the JITU and the owner of the loan position.
    // Not going to do that for the sake of this demo
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
        // Adding a transferFrom and approve so that function takes funds from callee and not from the contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(lendingPool), amount);
        lendingPool.deposit(asset, amount, address(this), 0);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        return lendingPool.withdraw(asset, amount, to);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode
    ) external returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(lendingPool), amount);
        return lendingPool.repay(asset, amount, rateMode, address(this));
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external {
        lendingPool.borrow(asset, amount, interestRateMode, 0, address(this));
        // Adding so that function borrows as the kAAVE contract, but delivers funds to the owner.
        IERC20(asset).transferFrom(address(this), msg.sender, amount);
    }

    function underwrite(address asset, uint256 amount)
        external
        returns (uint256)
    {
        // Adding a transferFrom and approve so that function takes funds from callee and not from the contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(lendingPool), amount);
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

    // Removed user argument since the position itself belongs to the contract
    // A liquidator calling preempt will be liquidating the contract's position
    function preempt(
        address collateralAsset,
        address debtAsset,
        uint256 debtToCover,
        bool receiveAToken
    ) external {
        uint256 collateralETH;
        uint256 totalDebtETH;
        uint256 liquidationThreshold;

        require(
            collateralAsset == state().bufferAsset,
            "Collateral Asset And Buffer Asset Must Be The Same!"
        );
        // Grab position information from the AAVE Lending Pool
        (collateralETH, totalDebtETH, , liquidationThreshold, , ) = lendingPool
            .getUserAccountData(address(this));
        // If there is no debt, don't do anything
        if (totalDebtETH == 0) {} else {
            // Use AAVE oracle to calculate collateral in ETH terms w/o the buffer
            ILendingPoolAddressesProvider poolAddressProvider =
                ILendingPoolAddressesProvider(
                    lendingPool.getAddressesProvider()
                );
            IPriceOracleGetter priceOracle =
                IPriceOracleGetter(poolAddressProvider.getPriceOracle());
            uint256 collateralUnitPrice =
                priceOracle.getAssetPrice(collateralAsset);
            uint256 debtUnitPrice = priceOracle.getAssetPrice(debtAsset);
            collateralETH = collateralETH.sub(
                collateralUnitPrice.wadMul(state().bufferAmount)
            );

            // Only do something if liquidation threshold is < 1 after buffer is removed
            if (
                (collateralETH.percentMul(liquidationThreshold)).wadDiv(
                    totalDebtETH
                ) >= HEALTH_FACTOR_LIQUIDATION_THRESHOLD
            ) {} else {
                // Transfer debt asset to the contract to repay and approve spending for AAVE lending pool
                IERC20(debtAsset).transferFrom(
                    msg.sender,
                    address(this),
                    debtToCover
                );
                IERC20(debtAsset).approve(address(lendingPool), debtToCover);
                // AAVE's LiquidationCall seems to burn variable debt before stable, so I am keeping the same practice.
                // reusing collateralETH to represent collateral to be seized by liquidator
                collateralETH = 0;
                // Attemp to repay variable debt first
                try
                    lendingPool.repay(debtAsset, debtToCover, 2, address(this))
                returns (uint256 variableRepayment) {
                    collateralETH = collateralETH.add(variableRepayment);
                } catch {}
                // If amount repaid is less than debtToCover specified, try and also pay off stable debt
                if (collateralETH < debtToCover) {
                    try
                        lendingPool.repay(
                            debtAsset,
                            debtToCover.sub(collateralETH),
                            1,
                            address(this)
                        )
                    returns (uint256 stableRepayment) {
                        collateralETH = collateralETH.add(stableRepayment);
                    } catch {}
                }

                if (receiveAToken) {
                    // Transfer aToken equivalents equal to the debt repaid in ETH terms
                    DataTypes.ReserveData memory collateralData =
                        lendingPool.getReserveData(collateralAsset);
                    IERC20(collateralData.aTokenAddress).transfer(
                        msg.sender,
                        (collateralETH.wadMul(debtUnitPrice)).wadDiv(
                            collateralUnitPrice
                        )
                    );
                } else {
                    // Withdraw collateral equal to the debt repaid in ETH terms
                    lendingPool.withdraw(
                        collateralAsset,
                        (collateralETH.wadMul(debtUnitPrice)).wadDiv(
                            collateralUnitPrice
                        ),
                        msg.sender
                    );
                }
            }
        }
    }
}
