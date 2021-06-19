// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { run, ethers } from "hardhat";
import { hrtime } from "process";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  await run("compile");
  const hre = require("hardhat");

  const whale_addr = "0x6555e1CC97d3cbA6eAddebBCD7Ca51d75771e0B8";

  const LendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
  const kaave = await ethers.getContractAt("KAAVE", "0x95401dc811bb5740090279ba06cfa8fcf6113778");
  const wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
  const usdc = await ethers.getContractAt("IERC20", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");

  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [whale_addr]}
  );
  const signer = await ethers.provider.getSigner(whale_addr);

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
  await kaave.connect(signer).deposit(wbtc.address, 1000000);
  await kaave.connect(signer).borrow(usdc.address, 111111, 1);
  await log_balances();
  await kaave.preempt(wbtc.address, usdc.address, signer._address, 111, false);
  
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
