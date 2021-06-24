
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
    const daiWhaleAddress = "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503";
  

    let wbtc: Contract, kaave: Contract, aaveLendingPool: Contract, dai: Contract;
    
    let wbtcWhale: Signer, secondWhale: Signer, ethWhale: Signer, daiWhale: Signer;
    

    before(async function () {
        wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
        dai = await ethers.getContractAt("IERC20", "0x6b175474e89094c44da98b954eedeac495271d0f");
        aaveLendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
    });

    beforeEach(async function () {

      wbtcWhale = await impersonateAddress(wbtcWhaleAddress);
      secondWhale = await impersonateAddress(secondWhaleAddress);
      ethWhale = await impersonateAddress(ethWhaleAddress);
      daiWhale = await impersonateAddress(daiWhaleAddress);

      var KAave = await ethers.getContractFactory("KAAVE");
      kaave = await KAave.deploy();
      await kaave.deployed();

      await wbtc.connect(wbtcWhale).approve(kaave.address, ethers.utils.parseEther("500"));
      await wbtc.connect(wbtcWhale).approve(aaveLendingPool.address, ethers.utils.parseEther("500"));
      //setting our jitu address
      await kaave.connect(secondWhale).setJitu(ethWhaleAddress);
      //giving the jitu some dai
      

      ethWhale.sendTransaction({
        to: wbtcWhaleAddress,
        value: ethers.utils.parseEther("3.0")
      })

      ethWhale.sendTransaction({
        to: daiWhaleAddress,
        value: ethers.utils.parseEther("3.0")
      })

      //await dai.connect(daiWhale).transfer(ethWhaleAddress, 10000);

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
      

    it("Should deposit through the lendingPool and through the hiding vault and expect user data to be the same", async function() {

        //check a quick transfer status
        var balance = await wbtc.balanceOf(wbtcWhale.getAddress());
        console.log("whale wbtc balance", balance.toNumber());
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
        expect(kaaveUserData.healthFactor).to.be.equal(poolUserData.healthFactor);
    });

    it("Should verify reversions", async function() {

        await kaave.connect(wbtcWhale).deposit(wbtc.address, ethers.utils.parseUnits('100', 8));
        await kaave.connect(wbtcWhale).borrow(dai.address, 1000, 2);

        await expect(kaave.connect(daiWhale).preempt(wbtc.address, dai.address, 100, true))
          .to.be.reverted;
        await expect(kaave.connect(ethWhale).preempt(wbtc.address, dai.address, 5000, true))
          .to.be.revertedWith('you are trying to repay too much debt');
    });

    it("Should be able to preempt a liquidation if lending position is unhealthy", async function() {

    });
  });