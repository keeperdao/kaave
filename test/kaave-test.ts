
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import AaveOracleABI from "../abi/AaveOracle.json";


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

    const wbtcWhaleAddress = "0x6555e1cc97d3cba6eaddebbcd7ca51d75771e0b8";
    const wethWhaleAddress = "0x0F4ee9631f4be0a63756515141281A3E2B293Bbe";
    const ethWhaleAddress = "0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B";
    const secondWhaleAddress = "0xe3dd3914ab28bb552d41b8dfe607355de4c37a51";
    const daiWhaleAddress = "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503";
    const aaveOracleOwner = "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5";
  

    let wbtc: Contract, kaave: Contract, aaveLendingPool: Contract, 
        dai: Contract, price: Contract, aaveOracle: Contract, variableDebtDai: Contract, awbtc: Contract, weth: Contract, aweth: Contract;
    
    let wbtcWhale: Signer, secondWhale: Signer, ethWhale: Signer, daiWhale: Signer, aaveOracleGovernance: Signer, wethWhale: Signer;
    

    before(async function () {
        wbtc = await ethers.getContractAt("IERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599");
        weth = await ethers.getContractAt("IERC20", "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        awbtc = await ethers.getContractAt("IERC20", "0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656");
        aweth = await ethers.getContractAt("IERC20", "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e");
        dai = await ethers.getContractAt("IERC20", "0x6b175474e89094c44da98b954eedeac495271d0f");
        variableDebtDai = await ethers.getContractAt("IERC20", "0x3F87b818f94F3cC21e47FD3Bf015E8D8183A3E08");
        aaveLendingPool = await ethers.getContractAt("ILendingPool", "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9");
        aaveOracle = new ethers.Contract("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", AaveOracleABI, ethers.provider);
    });

    beforeEach(async function () {

      wbtcWhale = await impersonateAddress(wbtcWhaleAddress);
      wethWhale = await impersonateAddress(wethWhaleAddress);
      secondWhale = await impersonateAddress(secondWhaleAddress);
      ethWhale = await impersonateAddress(ethWhaleAddress);
      daiWhale = await impersonateAddress(daiWhaleAddress);
      aaveOracleGovernance = await impersonateAddress(aaveOracleOwner);

      var KAave = await ethers.getContractFactory("KAAVE");
      kaave = await KAave.deploy();
      await kaave.deployed();

      var Price = await ethers.getContractFactory("Price");
      price = await Price.deploy();
      await price.deployed();
      

      ethWhale.sendTransaction({
        to: wbtcWhaleAddress,
        value: ethers.utils.parseEther("1.0")
      })

      ethWhale.sendTransaction({
        to: secondWhaleAddress,
        value: ethers.utils.parseEther("1.0")
      })

      ethWhale.sendTransaction({
        to: wethWhaleAddress,
        value: ethers.utils.parseEther("1.0")
      })

      ethWhale.sendTransaction({
        to: daiWhaleAddress,
        value: ethers.utils.parseEther("1.0")
      })

      ethWhale.sendTransaction({
        to: aaveOracleOwner,
        value: ethers.utils.parseEther("0.5")
      })
      //await dai.connect(daiWhale).transfer(ethWhaleAddress, 10000);
      await weth.connect(wethWhale).approve(kaave.address, ethers.utils.parseUnits('500', 18));
      await weth.connect(wethWhale).approve(aaveLendingPool.address, ethers.utils.parseUnits('500', 18));
      await wbtc.connect(wbtcWhale).approve(kaave.address, ethers.utils.parseUnits('500', 8));
      await wbtc.connect(wbtcWhale).approve(aaveLendingPool.address, ethers.utils.parseUnits('500', 8));

      //setting our jitu address
      await kaave.connect(secondWhale).setJitu(daiWhaleAddress);
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
        await kaave.connect(wbtcWhale).borrow(dai.address, ethers.utils.parseUnits('1000', 8), 2);

        const kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
        console.log("kaave vault health factor", kaaveVaultUserData.totalDebtETH.toString());

        await expect(kaave.connect(secondWhale).preempt(wbtc.address, dai.address, 100, true))
          .to.be.reverted;

        await kaave.connect(secondWhale).setJitu(ethWhaleAddress);
    
        await expect(kaave.connect(ethWhale).preempt(wbtc.address, dai.address, ethers.utils.parseUnits('5000', 8), true))
          .to.be.revertedWith('you are trying to repay too much debt');

        const balanceBefore = await wbtc.balanceOf(ethWhale.getAddress());
        console.log("balance before", balanceBefore.toString());
        await kaave.connect(ethWhale).preempt(wbtc.address, dai.address, ethers.utils.parseUnits('500', 8), false);
        const balanceAfter = await wbtc.balanceOf(ethWhale.getAddress());
        console.log("balance before", balanceAfter.toString());
    });

    //WETH version
    it("WETH version, should be able to preempt a liquidation if lending position is unhealthy", async function() {
      var balance = await weth.balanceOf(wethWhale.getAddress());
      var balanceDai = await dai.balanceOf(kaave.address);
      console.log("whale weth balance", balance.toString());
      console.log("kaave vault dai balance", balanceDai.toString());

      console.log("deposit one weth");
      await kaave.connect(wethWhale).deposit(weth.address, ethers.utils.parseUnits('30', 18));
      balance = await weth.balanceOf(wethWhale.getAddress());
      console.log("whale weth balance", balance.toString());

      console.log("borrow 20k dai");
      await kaave.connect(wethWhale).borrow(dai.address, ethers.utils.parseUnits('20000', 18), 2);
      balanceDai = await dai.balanceOf(kaave.address);
      console.log("vault dai balance", balanceDai.toString());
      expect(balanceDai.toString()).to.be.equal('20000000000000000000000');

      console.log("check health factor");
      var kaaveVaultUserData = await aaveLendingPool.connect(wethWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor", kaaveVaultUserData.healthFactor.toString());

      console.log("check health factor decrease after borrowing 20k dai more");
      await kaave.connect(wethWhale).borrow(dai.address, ethers.utils.parseUnits('20000', 18), 2);
      kaaveVaultUserData = await aaveLendingPool.connect(wethWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor post borrow more", kaaveVaultUserData.healthFactor.toString());

      console.log("underwrite some collateral and health factor should increase");
      await kaave.connect(wethWhale).underwrite(weth.address, ethers.utils.parseUnits('15', 18));
      kaaveVaultUserData = await aaveLendingPool.connect(wethWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor post underwriting", kaaveVaultUserData.healthFactor.toString());

      //check (block: 12522000) and update dai price
      var daiPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(dai.address);
      console.log("current dai price from aave oracle is:", daiPrice.toString());
      await aaveOracle.connect(aaveOracleGovernance).setAssetSources([dai.address], [price.address]);
      daiPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(dai.address);
      console.log("new dai price from aave oracle is:", daiPrice.toString());
      kaaveVaultUserData = await aaveLendingPool.connect(wethWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor", kaaveVaultUserData.healthFactor.toString());

      //check debt and aToken balances
      const variableDebtBalance = await variableDebtDai.balanceOf(kaave.address);
      console.log("dai variable debt balance of hiding vault is:", variableDebtBalance.toString());
      console.log("kaave vault total debt is ~80 ethers (match):", kaaveVaultUserData.totalDebtETH.toString());
      const aTokenBalance = await aweth.connect(wethWhale).balanceOf(kaave.address);
      console.log("aweth balance of vault is:", aTokenBalance.toString());

      //preempt liquidation by dai whale and check weth balances
      kaaveVaultUserData = await aaveLendingPool.connect(wethWhale).getUserAccountData(kaave.address);
      console.log("kaave vault liquidation threshold", kaaveVaultUserData.currentLiquidationThreshold.toString());
      //below approval is used as part of the transfer of dai upon preempted liquidation
      await dai.connect(daiWhale).approve(kaave.address, ethers.utils.parseUnits('2000000', 18));
      const wethPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(weth.address);
      console.log("weth price:", wethPrice.toString());
      var balanceWethLiquidator = await aweth.balanceOf(daiWhale.getAddress());
      console.log("liquidator weth balance", balanceWethLiquidator.toString());
      await kaave.connect(daiWhale).preempt(weth.address, dai.address, ethers.utils.parseUnits('1000', 18), true);
      balanceWethLiquidator = await aweth.balanceOf(daiWhale.getAddress());
      console.log("new liquidator weth balance", balanceWethLiquidator.toString());
    });

    //SKIPPING WBTC TEST FOR NOW
    /*
    it("Should be able to preempt a liquidation if lending position is unhealthy", async function() {
      var balance = await wbtc.balanceOf(wbtcWhale.getAddress());
      var balanceDai = await dai.balanceOf(kaave.address);
      console.log("whale wbtc balance", balance.toNumber());
      console.log("kaave vault dai balance", balanceDai.toNumber());

      console.log("deposit one wbtc");
      await kaave.connect(wbtcWhale).deposit(wbtc.address, ethers.utils.parseUnits('2', 8));
      balance = await wbtc.balanceOf(wbtcWhale.getAddress());
      console.log("whale wbtc balance", balance.toNumber());

      console.log("borrow 20k dai");
      await kaave.connect(wbtcWhale).borrow(dai.address, ethers.utils.parseUnits('20000', 18), 2);
      balanceDai = await dai.balanceOf(kaave.address);
      console.log("vault dai balance", balanceDai.toString());
      expect(balanceDai.toString()).to.be.equal('20000000000000000000000');

      console.log("check health factor");
      var kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor", kaaveVaultUserData.healthFactor.toString());

      console.log("check health factor decrease after borrowing 20k dai more");
      await kaave.connect(wbtcWhale).borrow(dai.address, ethers.utils.parseUnits('20000', 18), 2);
      kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor post borrow more", kaaveVaultUserData.healthFactor.toString());

      console.log("underwrite some collateral and health factor should increase");
      await kaave.connect(wbtcWhale).underwrite(wbtc.address, ethers.utils.parseUnits('1', 8));
      kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor post underwriting", kaaveVaultUserData.healthFactor.toString());

      //check (block: 12522000) and update dai price
      var daiPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(dai.address);
      console.log("current dai price from aave oracle is:", daiPrice.toString());
      await aaveOracle.connect(aaveOracleGovernance).setAssetSources([dai.address], [price.address]);
      daiPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(dai.address);
      console.log("new dai price from aave oracle is:", daiPrice.toString());
      kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
      console.log("kaave vault health factor", kaaveVaultUserData.healthFactor.toString());

      //check debt and aToken balances
      const variableDebtBalance = await variableDebtDai.balanceOf(kaave.address);
      console.log("dai variable debt balance of hiding vault is:", variableDebtBalance.toNumber());
      console.log("kaave vault total debt is ~80 ethers (match):", kaaveVaultUserData.totalDebtETH.toString());
      const aTokenBalance = await awbtc.connect(wbtcWhale).balanceOf(kaave.address);
      console.log("awbtc balance of vault is:", aTokenBalance.toString());

      //preempt liquidation by dai whale
      kaaveVaultUserData = await aaveLendingPool.connect(wbtcWhale).getUserAccountData(kaave.address);
      console.log("kaave vault liquidation threshold", kaaveVaultUserData.currentLiquidationThreshold.toString());
      //below approval is used as part of the transfer of dai upon preempted liquidation
      await dai.connect(daiWhale).approve(kaave.address, ethers.utils.parseUnits('2000000', 18));
      const wbtcPrice = await aaveOracle.connect(aaveOracleGovernance).getAssetPrice(wbtc.address);
      console.log("wbtc price:", wbtcPrice.toString());
      var balanceWBtcLiquidator = await awbtc.balanceOf(daiWhale.getAddress());
      console.log("liquidator weth balance", balanceWBtcLiquidator.toString());
      await kaave.connect(daiWhale).preempt(wbtc.address, dai.address, ethers.utils.parseUnits('2000', 18), true);
      balanceWBtcLiquidator = await awbtc.balanceOf(daiWhale.getAddress());
      console.log("new liquidator weth balance", balanceWBtcLiquidator.toString());

    });
    */
  });