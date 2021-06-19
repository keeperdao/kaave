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
  const usdc = await ethers.getContractAt("IERC20", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
  
  const SettablePriceOracle = await ethers.getContractAt("SettablePriceOracle", "0x998abeb3E57409262aE5b751f60747921B33613E");
  
  async function switchPriceOracleForWbtc() {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [aaveOracleOwner]}
    );
    const signer = await ethers.provider.getSigner(aaveOracleOwner);
    const wbtcPrice = await AaveOracle.connect(signer).getAssetPrice(wbtc.address);
    await SettablePriceOracle.setPrice(wbtcPrice.div(2));
    const discountedPrice = await SettablePriceOracle.getAssetPrice(wbtc.address);
    console.log('wbtc price', wbtcPrice.toString());
    console.log('discounted price', discountedPrice.toString());
    await AaveOracle.connect(signer).setFallbackOracle(SettablePriceOracle.address);
    await AaveOracle.connect(signer).setAssetSources([wbtc.address], [zero_addr]);
    const aavePrice = await AaveOracle.getAssetPrice(wbtc.address);
    console.log('aave price for wbtc', aavePrice.toString());
    const usdcPrice2 = await AaveOracle.getAssetPrice(usdc.address);
    console.log('usdc price', usdcPrice2.toString());
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [aaveOracleOwner]}
    )
    console.log("using discounted price oracle");

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
    var balance = await wbtc.balanceOf(signer._address);
    console.log("user's wbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(signer._address);
    console.log("user's usdc balance", balance.toNumber());
    balance = await wbtc.balanceOf(kaave.address);
    console.log("kaave's wbtc balance", balance.toNumber());
    balance = await usdc.balanceOf(kaave.address);
    console.log("kaave's usdc balance", balance.toNumber());
  }

  await log_balances();
  await wbtc.connect(signer).approve(kaave.address, 2000000)
  await kaave.connect(signer).deposit(wbtc.address, 30000);
  await kaave.connect(signer).borrow(usdc.address, 5000000, 1);
  await log_balances();
  await kaave.connect(signer).underwrite(wbtc.address, 1000);
  await switchPriceOracleForWbtc();
  await usdc.connect(signer).approve(kaave.address, 1111111111);
  await kaave.connect(signer).preempt(wbtc.address, usdc.address, signer._address, 11111111, false);
  
  // await wbtc.connect(signer).approve(LendingPool.address, 2000000);
  // await LendingPool.connect(signer).deposit(wbtc.address, 30000, signer._address, 0);
  // await LendingPool.connect(signer).borrow(usdc.address, 5000000, 1, 0, signer._address);
  // await switchPriceOracleForWbtc();
  // const userData = await LendingPool.connect(signer).getUserAccountData(signer._address);
  // console.log(userData.totalCollateralETH.toString());
  // console.log(userData.totalDebtETH.toString());
  // console.log(userData.currentLiquidationThreshold.toString());
  // console.log(userData.healthFactor.toString());
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

