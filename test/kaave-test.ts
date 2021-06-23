
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";


async function impersonateAddress(address: string) {
    await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [address],
    });
    let signer = await ethers.provider.getSigner(address);
    return signer;
};

describe("Token", function () {
    let accounts: Signer[];
    const wbtcWhaleAddress = "0x6555e1cc97d3cba6eaddebbcd7ca51d75771e0b8";

    let wbtc: Contract, kaave: Contract, aaveLendingPool: Contract;
    
    let wbtcWhale: Signer;
    

    before(async function () {
        wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
        aaveLendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
    });

    beforeEach(async function () {

      wbtcWhale = await impersonateAddress(wbtcWhaleAddress);

      var KAave = await ethers.getContractFactory("KAAVE");
      kaave = await KAave.deploy();

      await wbtc.connect(wbtcWhale).approve(kaave.address, 10000);
      await wbtc.connect(wbtcWhale).approve(aaveLendingPool.address, 10000);
    });
    
    it("Should print some balances", async function() {
        var balance = await wbtc.balanceOf(wbtcWhale.getAddress());
        console.log("whale wbtc balance", balance.toNumber());
    });

    it("Should be able to deposit through the vault and verify user data", async function() {
        await kaave.connect(wbtcWhale).deposit(wbtc.address, 5000);
        await aaveLendingPool.connect(wbtcWhale).deposit(wbtc.address, 5000, wbtcWhaleAddress, 0);

        const kaaveUserData = aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
        const wbtcWhaleUserData = aaveLendingPool.connect(wbtcWhale).getUserAccountData(wbtcWhale.getAddress());

        console.log("whale wbtc totalCollateralETH", wbtcWhaleUserData.totalCollateralETH);
        console.log("whale wbtc healthFactor", kaaveUserData.healthFactor);
        console.log("wbtc vault healthFactor", wbtcWhaleUserData.healthFactor);
        expect(kaaveUserData.healthFactor).to.be.equal(wbtcWhaleUserData.healthFactor);
    });
  });