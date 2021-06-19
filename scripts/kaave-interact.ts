// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { run, ethers } from "hardhat";
import { hrtime } from "process";
import AaveOracleABI from "../abis/AaveOracle.json";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  await run("compile");
  const hre = require("hardhat");

  const whale_addr = "0x6555e1CC97d3cbA6eAddebBCD7Ca51d75771e0B8";
  const zero_addr = "0x0000000000000000000000000000000000000000";

  const LendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
  const LendingPoolAddressProvider = await ethers.getContractAt("ILendingPoolAddressesProvider", "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5");
  const AaveOracle = new ethers.Contract("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", AaveOracleABI, ethers.provider);
  const aaveOracleOwner = "0xee56e2b3d491590b5b31738cc34d5232f378a8d5";
  const kaave = await ethers.getContractAt("KAAVE", "0x95401dc811bb5740090279ba06cfa8fcf6113778");
  const wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
  const awbtc = await ethers.getContractAt("IERC20", "0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656");
  const usdc = await ethers.getContractAt("IERC20", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
  const ausdc = await ethers.getContractAt("IERC20", "0xBcca60bB61934080951369a648Fb03DF4F96263C");
  
  const SettablePriceOracle = await ethers.getContractAt("SettablePriceOracle", "0x998abeb3E57409262aE5b751f60747921B33613E");
  
  async function switchPriceOracleForWbtc() {
    console.log("SWITCHING BTC PRICE ORACLE============")
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [aaveOracleOwner]}
    );
    const signer = await ethers.provider.getSigner(aaveOracleOwner);
    const wbtcPrice = await AaveOracle.connect(signer).getAssetPrice(wbtc.address);
    await SettablePriceOracle.setPrice(wbtcPrice.div(2));
    const discountedPrice = await SettablePriceOracle.getAssetPrice(wbtc.address);
    console.log('aave oracle wbtc price', wbtcPrice.toString());
    console.log('discounted price', discountedPrice.toString());
    await AaveOracle.connect(signer).setFallbackOracle(SettablePriceOracle.address);
    await AaveOracle.connect(signer).setAssetSources([wbtc.address], [zero_addr]);
    console.log('switched btc price oracle');
    const aavePrice = await AaveOracle.getAssetPrice(wbtc.address);
    console.log('aave oracle wbtc price', aavePrice.toString());
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [aaveOracleOwner]}
    )
    console.log("using discounted price oracle\n");

  }

  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [whale_addr]}
  );
  const signer = await ethers.provider.getSigner(whale_addr);
  signer.sendTransaction({
    to: aaveOracleOwner,
    value: ethers.utils.parseEther("5.0")
  })

  async function log_balances() {
    console.log("ACCOUNT BALANCES================")
    var balance = await wbtc.balanceOf(signer._address);
    console.log("user's wbtc balance", balance.toNumber());
    balance = await awbtc.balanceOf(signer._address);
    console.log("user's awbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(signer._address);
    console.log("user's usdc balance", balance.toNumber());
    balance = await ausdc.balanceOf(signer._address);
    console.log("user's ausdc balance", balance.toNumber());
    balance = await wbtc.balanceOf(kaave.address);
    console.log("kaave's wbtc balance", balance.toNumber());
    balance = await awbtc.balanceOf(kaave.address);
    console.log("kaave's awbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(kaave.address);
    console.log("kaave's usdc balance", balance.toNumber());
    balance = await ausdc.balanceOf(kaave.address);
    console.log("kaave's ausdc balance", balance.toNumber());
    console.log("\n")

  }

  async function log_kaave_account_data() {
    console.log("KAAVE ACCOUNT DATA================")
    const userData = await kaave.connect(signer).getUserAccountData(signer._address);
    console.log('Total collateral in Eth:',userData.totalCollateralETH.toString());
    console.log('Total debt in Eth:', userData.totalDebtETH.toString());
    console.log('Liquidation threshold:', userData.currentLiquidationThreshold.toString());
    console.log('Health factor:',userData.healthFactor.toString());
    console.log("\n")
  }

  async function log_aave_account_data() {
    console.log("AAVE ACCOUNT DATA================")
    const userData = await LendingPool.connect(signer).getUserAccountData(signer._address);
    console.log('Total collateral in Eth:',userData.totalCollateralETH.toString());
    console.log('Total debt in Eth:', userData.totalDebtETH.toString());
    console.log('Liquidation threshold:', userData.currentLiquidationThreshold.toString());
    console.log('Health factor:',userData.healthFactor.toString());
    console.log("\n")
  }

  await log_balances();
  await wbtc.connect(signer).approve(kaave.address, 2000000)
  await kaave.connect(signer).deposit(wbtc.address, 30000);
  console.log("Deposited into kaave\n");
  await kaave.connect(signer).borrow(usdc.address, 4500000, 1);
  console.log("Borrowed from kaave\n");
  await log_balances();
  await log_kaave_account_data();
  await kaave.connect(signer).underwrite(wbtc.address, 1000);
  console.log("Underwrote kaave position\n");
  await log_balances();
  await log_kaave_account_data();
  await switchPriceOracleForWbtc();
  await log_kaave_account_data();
  await usdc.connect(signer).approve(kaave.address, 1111111111);
  await kaave.connect(signer).preempt(wbtc.address, usdc.address, signer._address, 11111111, false);
  console.log("Preempted unhealthy position\n");
  await log_kaave_account_data();
  await log_balances();
  
  // await wbtc.connect(signer).approve(LendingPool.address, 2000000);
  // await LendingPool.connect(signer).deposit(wbtc.address, 30000, signer._address, 0);
  // console.log("Deposited into aave\n");
  // await LendingPool.connect(signer).borrow(usdc.address, 4500000, 1, 0, signer._address);
  // console.log("Borrowed from aave\n");
  // await log_aave_account_data();
  // await switchPriceOracleForWbtc();
  // await log_aave_account_data();
  // await log_balances();
  // await usdc.connect(signer).approve(LendingPool.address, 1111111111);
  // await LendingPool.connect(signer).liquidationCall(wbtc.address, usdc.address, signer._address, 11111111, false);
  // await log_balances();

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

