import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import AaveOracleABI from "../abis/AaveOracle.json";

describe("Kaave", function() {
  const hre = require("hardhat");
  let kaave: Contract, SettablePriceOracle: Contract, LendingPool: Contract, 
    LendingPoolAddressProvider: Contract, AaveOracle: Contract, 
    wbtc: Contract, awbtc: Contract, usdc: Contract, ausdc: Contract;
  const aaveOracleOwnerAdd = "0xee56e2b3d491590b5b31738cc34d5232f378a8d5";
  const borrowerAddr = "0x6555e1CC97d3cbA6eAddebBCD7Ca51d75771e0B8";
  const strategistAddr = "0xf9356a8ac2439694580521c2dCA2929A155b223C";
  const zero_addr = "0x0000000000000000000000000000000000000000";
  let borrower: Signer, aaveOracleOwner: Signer, strategist: Signer;

  async function log_balances() {
    console.log("ACCOUNT BALANCES================")
    var balance = await wbtc.balanceOf(borrower.getAddress());
    console.log("user's wbtc balance", balance.toNumber());
    balance = await awbtc.balanceOf(borrower.getAddress());
    console.log("user's awbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(borrower.getAddress());
    console.log("user's usdc balance", balance.toNumber());
    balance = await ausdc.balanceOf(borrower.getAddress());
    console.log("user's ausdc balance", balance.toNumber());
    balance = await wbtc.balanceOf(kaave.address);
    console.log("kaave's wbtc balance", balance.toNumber());
    balance = await awbtc.balanceOf(kaave.address);
    console.log("kaave's awbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(kaave.address);
    console.log("kaave's usdc balance", balance.toNumber());
    balance = await ausdc.balanceOf(kaave.address);
    console.log("strategist's ausdc balance", balance.toNumber());
    balance = await wbtc.balanceOf(strategist.getAddress());
    console.log("strategist's wbtc balance", balance.toNumber());
    balance = await awbtc.balanceOf(strategist.getAddress());
    console.log("strategist's awbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(strategist.getAddress());
    console.log("strategist's usdc balance", balance.toNumber());
    balance = await ausdc.balanceOf(strategist.getAddress());
    console.log("strategist's ausdc balance", balance.toNumber());
    
    console.log("\n")

  }

  async function impersonate(addr: string) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [addr]}
    );
    let signer = await ethers.provider.getSigner(addr); 
    return signer
  }
  
  before(async function () {
    LendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
    LendingPoolAddressProvider = await ethers.getContractAt("ILendingPoolAddressesProvider", "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5");
    AaveOracle = new ethers.Contract("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", AaveOracleABI, ethers.provider);
    wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
    awbtc = await ethers.getContractAt("IERC20", "0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656");
    usdc = await ethers.getContractAt("IERC20", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
    ausdc = await ethers.getContractAt("IERC20", "0xBcca60bB61934080951369a648Fb03DF4F96263C");
  });

  beforeEach(async function () {
    var kaaveFactory = await ethers.getContractFactory("KAAVE");
    kaave = await kaaveFactory.deploy();
    var oracleFactory = await ethers.getContractFactory("SettablePriceOracle");
    SettablePriceOracle = await oracleFactory.deploy();
    borrower = await impersonate(borrowerAddr);
    aaveOracleOwner = await impersonate(aaveOracleOwnerAdd);
    strategist = await impersonate(strategistAddr);
    borrower.sendTransaction({
      to: aaveOracleOwnerAdd,
      value: ethers.utils.parseEther("5.0")
    })
    borrower.sendTransaction({
      to: strategistAddr,
      value: ethers.utils.parseEther("5.0")
    })
    await wbtc.connect(borrower).approve(kaave.address, 2000000);
    await wbtc.connect(borrower).approve(LendingPool.address, 2000000);
    await usdc.connect(strategist).approve(kaave.address, 1111111111);
    await usdc.connect(strategist).approve(LendingPool.address, 1111111111);

    // install settable price oracle for wbtc
    const wbtcPrice = await AaveOracle.getAssetPrice(wbtc.address);
    await SettablePriceOracle.setPrice(wbtcPrice);
    await AaveOracle.connect(aaveOracleOwner).setFallbackOracle(SettablePriceOracle.address);
    await AaveOracle.connect(aaveOracleOwner).setAssetSources([wbtc.address], [zero_addr]);
  });

  afterEach(async function () {
    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [{
        forking: {
          jsonRpcUrl: hre.network.config.forking.url,
          blockNumber: hre.network.config.forking.blockNumber
        }
      }]
    })
  });
  
  it("Should match position health factor for identical positions on Aave without buffer", async function() {
    await kaave.connect(borrower).deposit(wbtc.address, 30000);
    await kaave.connect(borrower).borrow(usdc.address, 4500000, 1);
    const kaaveUserData = await kaave.connect(borrower).getUserAccountData(borrower.getAddress());

    await LendingPool.connect(borrower).deposit(wbtc.address, 30000, borrower.getAddress(), 0);
    await LendingPool.connect(borrower).borrow(usdc.address, 4500000, 1, 0, borrower.getAddress());
    const aaveUserData = await LendingPool.connect(borrower).getUserAccountData(borrower.getAddress());

    expect(kaaveUserData.totalCollateralETH.toNumber()).to.not.equal(0);
    expect(kaaveUserData.totalDebtETH.toNumber()).to.not.equal(0);
    expect(kaaveUserData.healthFactor).to.equal(aaveUserData.healthFactor);

  });

  it("Should match position health factor for identical positions on Aave with buffer", async function() {
    await kaave.connect(borrower).deposit(wbtc.address, 30000);
    await kaave.connect(borrower).borrow(usdc.address, 4500000, 1);
    await kaave.connect(borrower).underwrite(wbtc.address, 900);
    const kaaveUserData = await kaave.connect(borrower).getUserAccountData(borrower.getAddress());

    await LendingPool.connect(borrower).deposit(wbtc.address, 30000, borrower.getAddress(), 0);
    await LendingPool.connect(borrower).borrow(usdc.address, 4500000, 1, 0, borrower.getAddress());
    const aaveUserData = await LendingPool.connect(borrower).getUserAccountData(borrower.getAddress());

    expect(kaaveUserData.totalCollateralETH.toNumber()).to.not.equal(0);
    expect(kaaveUserData.totalDebtETH.toNumber()).to.not.equal(0);
    expect(kaaveUserData.healthFactor).to.equal(aaveUserData.healthFactor);

  });

  it ("Should not allow liquidations of healthy positions", async function() {
    await kaave.connect(borrower).deposit(wbtc.address, 30000);
    await kaave.connect(borrower).borrow(usdc.address, 4500000, 1);
    await kaave.connect(strategist).underwrite(usdc.address, 10000000);
    await expect ( 
      kaave.connect(strategist).preempt(wbtc.address, usdc.address, strategist.getAddress(), 11111111, false)
    ).to.be.revertedWith("42");

    await LendingPool.connect(borrower).deposit(wbtc.address, 30000, borrower.getAddress(), 0);
    await LendingPool.connect(borrower).borrow(usdc.address, 4500000, 1, 0, borrower.getAddress());
    await expect (
      LendingPool.connect(strategist).liquidationCall(wbtc.address, usdc.address, borrower.getAddress(), 11111111, false)
    ).to.be.revertedWith("42");

  });

  it ("Should allow liquidations of unhealthy positions", async function() {
    await kaave.connect(borrower).deposit(wbtc.address, 30000);
    await kaave.connect(borrower).borrow(usdc.address, 4500000, 1);
    await kaave.connect(strategist).underwrite(usdc.address, 10000000);

    await LendingPool.connect(borrower).deposit(wbtc.address, 30000, borrower.getAddress(), 0);
    await LendingPool.connect(borrower).borrow(usdc.address, 4500000, 1, 0, borrower.getAddress());

    const wbtcPrice = await SettablePriceOracle.getAssetPrice(wbtc.address);
    await SettablePriceOracle.setPrice(wbtcPrice.div(2));

  
    var btcBalancePreKaaveLiquidation = await wbtc.balanceOf(strategist.getAddress());
    await kaave.connect(strategist).preempt(wbtc.address, usdc.address, strategist.getAddress(), 11111111, false);
    var btcBalanceAfterKaaveLiquidation = await wbtc.balanceOf(strategist.getAddress());
    await LendingPool.connect(strategist).liquidationCall(wbtc.address, usdc.address, borrower.getAddress(), 11111111, false);
    var btcBalanceAfterAaveLiquidation = await wbtc.balanceOf(strategist.getAddress());
    
    // check strategist's balance of collateral asset increases
    expect(btcBalanceAfterKaaveLiquidation.toNumber()).to.be.greaterThan(btcBalancePreKaaveLiquidation.toNumber());
    expect(btcBalanceAfterAaveLiquidation.toNumber()).to.be.greaterThan(btcBalanceAfterKaaveLiquidation.toNumber());
    // check strategist received same amount of collateral in kaave and aave liquidation
    expect(
      btcBalanceAfterAaveLiquidation.toNumber() - btcBalanceAfterKaaveLiquidation.toNumber()
      ).to.equal(
        btcBalanceAfterKaaveLiquidation.toNumber() - btcBalancePreKaaveLiquidation.toNumber()
      )
  });
});