
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, providers, Signer } from "ethers";


describe("Token", function () {

    const hre = require("hardhat");
    async function impersonateAddress(address: string) {
        await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [address],
        });
        let signer = await ethers.provider.getSigner(address);
        return signer;
    };

    let accounts: Signer[];
    const wbtcWhaleAddress = "0x6555e1cc97d3cba6eaddebbcd7ca51d75771e0b8";
    const ethWhaleAddress = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B";
    const secondWhaleAddress = "0xe3dd3914ab28bb552d41b8dfe607355de4c37a51";

    let wbtc: Contract, kaave: Contract, aaveLendingPool: Contract;
    
    let wbtcWhale: Signer, secondWhale: Signer, ethWhale: Signer;
    

    before(async function () {
        wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
        aaveLendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
    });

    beforeEach(async function () {

      wbtcWhale = await impersonateAddress(wbtcWhaleAddress);
      secondWhale = await impersonateAddress(secondWhaleAddress);
      ethWhale = await impersonateAddress(ethWhaleAddress);

      var KAave = await ethers.getContractFactory("KAAVE");
      kaave = await KAave.deploy();
      await kaave.deployed();

      await wbtc.connect(wbtcWhale).approve(kaave.address, ethers.utils.parseEther("500"));
      await wbtc.connect(wbtcWhale).approve(aaveLendingPool.address, ethers.utils.parseEther("500"));
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


    it.only("Should deposit through the lendingPool and through the hiding vault and expect user data to be the same", async function() {

        //check a quick transfer status
        var balance = await wbtc.balanceOf(wbtcWhale.getAddress());
        console.log("whale wbtc balance", balance.toNumber());
        ethWhale.sendTransaction({
            to: wbtcWhaleAddress,
            value: ethers.utils.parseEther("5.0")
          })
        console.log("lending pool", aaveLendingPool.address);
        console.log("kaave", kaave.address);
        await wbtc.connect(wbtcWhale).approve(kaave.address, 500);
        await wbtc.connect(wbtcWhale).transfer(kaave.address, 100);
        console.log("whale wbtc balance", (await wbtc.balanceOf(kaave.address)).toNumber());
        console.log("whale wbtc balance", (await wbtc.balanceOf(wbtcWhaleAddress)).toNumber());

        //interaction with the deposit function of the vault
        await kaave.connect(wbtcWhale).deposit(wbtc.address, 100);
        console.log("whale wbtc balance", (await wbtc.balanceOf(wbtcWhaleAddress)).toNumber());

        await aaveLendingPool.connect(wbtcWhale).deposit(wbtc.address, 100, wbtcWhaleAddress, 0);
        console.log("whale wbtc balance", (await wbtc.balanceOf(wbtcWhaleAddress)).toNumber());
        
        const kaaveUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(wbtcWhaleAddress);
        const poolUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
        console.log("kaave user data", kaaveUserData.totalCollateralETH.toNumber());
        console.log("pool user data", poolUserData.totalCollateralETH.toNumber());

        expect(kaaveUserData.totalCollateralETH).to.be.equal(poolUserData.totalCollateralETH);
    });

    it("Should be able to deposit through the vault and verify user data", async function() {
        await kaave.connect(wbtcWhale).deposit(wbtc.address, ethers.utils.parseEther("100"));
        await aaveLendingPool.connect(wbtcWhale).deposit(wbtc.address, ethers.utils.parseEther("100"), wbtcWhaleAddress, 0);
        console.log("balance", (await (wbtc.balanceOf(wbtcWhale.getAddress()))).toNumber());
        await wbtc.connect(wbtcWhale).transfer(kaave.address, ethers.utils.parseEther("100"));
        console.log("balance2", (await (wbtc.balanceOf(wbtcWhale.getAddress()))).toNumber());

        const kaaveUserData = aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
        const wbtcWhaleUserData = aaveLendingPool.connect(wbtcWhale).getUserAccountData(wbtcWhale.getAddress());

        console.log("lending pool", aaveLendingPool.address);
        console.log("whale wbtc totalCollateralETH", wbtcWhaleUserData.totalCollateralETH);
        console.log("whale wbtc healthFactor", kaaveUserData.healthFactor);
        console.log("wbtc vault healthFactor", wbtcWhaleUserData.healthFactor);
        expect(kaaveUserData.healthFactor).to.be.equal(wbtcWhaleUserData.healthFactor);
    });
  });