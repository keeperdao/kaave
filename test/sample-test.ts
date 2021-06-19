import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Signer } from "ethers";
import OracleABI from "./AaveOracle.json";
import wethABI from "./wETH.json";
import daiABI from "./Dai.json";
import atokenABI from "./AToken.json";

describe("kAAVE-Test", function () {
  let accounts: Signer[];
  const DAI_WHALE_ADDRESS = "0xd624790fc3e318ce86f509ecf69df440b3fc328d";
  const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  const ADAI_ADDRESS = "0x028171bCA77440897B824Ca71D1c56caC55b68A3";
  const POOL_ADDRESS = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";
  const ORACLE_ADDRESS = "0xA50ba011c48153De246E5192C8f9258A2ba79Ca9";
  const ORACLE_OWNER_ADDRESS = "0xEE56e2B3D491590B5b31738cC34d5232F378a8D5";

  beforeEach(async function () {
    accounts = await ethers.getSigners();
    await hre.network.provider.request({
      method: "hardhat_reset",
      params: [{
        forking: {
          jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
          blockNumber: 12632000,
        },
      }]
    })
  });

  it("kAAVE-receiveAToken-False", async function () {
    let tx;
    const TEST1_ADDRESS = await accounts[0].getAddress();
    const TEST2_ADDRESS = await accounts[1].getAddress();

    const kAAVEContract = await ethers.getContractFactory("KAAVE");
    const kAAVE = await kAAVEContract.deploy();
    await kAAVE.deployed();

    // deploy contract to return fake price to AaveOracle
    // fakePrice contract sets DAI/ETH to ~ 0.000213555 ETH or $0.49 as of 6/18/2021
    const fakePriceContract = await ethers.getContractFactory("fakePrice");
    const fakePrice = await fakePriceContract.deploy();
    await fakePrice.deployed();

    console.log("Impersonating DAI whale...");
    // impersonate DAI whale
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [DAI_WHALE_ADDRESS]
    }
    );
    const daiWhale = await ethers.provider.getSigner(DAI_WHALE_ADDRESS);
    const dai = new ethers.Contract(DAI_ADDRESS, daiABI, daiWhale);
    const weth = new ethers.Contract(WETH_ADDRESS, wethABI, accounts[0]);

    console.log("Using DAI whale to send 10000 DAI to test addresses...");
    await dai.push(TEST1_ADDRESS, ethers.utils.parseEther("10000"));
    await dai.push(TEST2_ADDRESS, ethers.utils.parseEther("2500"));
    expect(await dai.balanceOf(TEST1_ADDRESS)).to.equal((ethers.utils.parseEther("10000")).toString());
    expect(await dai.balanceOf(TEST2_ADDRESS)).to.equal((ethers.utils.parseEther("2500")).toString());

    console.log("Account 1 depositing 5000 DAI into kAAVE...");
    await dai.connect(accounts[0]).approve(kAAVE.address, ethers.utils.parseEther("5000"));
    await kAAVE.connect(accounts[0]).deposit(DAI_ADDRESS, ethers.utils.parseEther("5000"));

    console.log("Account 2 underwriting position with 50% additional buffer...")
    await dai.connect(accounts[1]).approve(kAAVE.address, ethers.utils.parseEther("2500"));
    await kAAVE.connect(accounts[1]).underwrite(DAI_ADDRESS, ethers.utils.parseEther("2500"));

    console.log("Account 1 borrows 0.9 ETH...");
    await kAAVE.connect(accounts[0]).borrow(WETH_ADDRESS, ethers.utils.parseEther("0.9"), 1);
    expect(await weth.balanceOf(TEST1_ADDRESS)).to.equal((ethers.utils.parseEther("0.9")).toString());

    console.log("Minting 3 WETH for Account 2...")
    await weth.connect(accounts[1]).deposit({ value: ethers.utils.parseEther("3") });
    expect(await weth.balanceOf(TEST2_ADDRESS)).to.equal((ethers.utils.parseEther("3")).toString());

    console.log("Account 2 attempting to call premptive liquidation...")
    await weth.connect(accounts[1]).approve(kAAVE.address, ethers.utils.parseEther("0.9"));
    await kAAVE.connect(accounts[1]).preempt(DAI_ADDRESS, WETH_ADDRESS, ethers.utils.parseEther("0.9"), false);

    console.log("Sending ETH from test account to oracle owner...");
    tx = await accounts[0].sendTransaction({
      to: ORACLE_OWNER_ADDRESS,
      value: ethers.utils.parseEther("3")
    });

    console.log("Grabbing oracle owner to impersonate...");
    // impersonate AAVE oracle owner
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ORACLE_OWNER_ADDRESS]
    });
    const oracleOwner = await ethers.provider.getSigner(ORACLE_OWNER_ADDRESS);

    let oraclePrice, debtInDAI;
    console.log("Fetching DAI/ETH price from oracle and calculating initial LTV...");
    const aaveOracle = new ethers.Contract(ORACLE_ADDRESS, OracleABI, oracleOwner);
    oraclePrice = await aaveOracle.getAssetPrice(DAI_ADDRESS);
    console.log("Initial DAI/ETH price: ", ethers.utils.formatUnits(oraclePrice));
    debtInDAI = (ethers.utils.parseEther("0.9")).div(oraclePrice);
    console.log("Initial debt in DAI: ", debtInDAI.toString());
    console.log("Initial LTV: ", Number(debtInDAI) / 5000);
    console.log("Initial LTV w/ buffer: ", Number(debtInDAI) / 7500);

    console.log("Taking control of oracle and modifying DAI/ETH price source...");
    await expect(aaveOracle.connect(oracleOwner).setAssetSources([DAI_ADDRESS], [fakePrice.address]))
      .to.emit(aaveOracle, 'AssetSourceUpdated')
      .withArgs(DAI_ADDRESS, fakePrice.address);
    oraclePrice = await aaveOracle.getAssetPrice(DAI_ADDRESS);
    console.log("Modified DAI/ETH price: ", ethers.utils.formatUnits(oraclePrice));
    debtInDAI = (ethers.utils.parseEther("0.9")).div(oraclePrice);
    console.log("Modified debt in DAI: ", debtInDAI.toString());
    console.log("Tasty LTV: ", Number(debtInDAI) / 5000);
    console.log("Tasty LTV w/ buffer: ", Number(debtInDAI) / 7500);

    console.log("Account 2 attempts to call preemptive liquidation now that LTV is within range...");
    await kAAVE.connect(accounts[1]).preempt(DAI_ADDRESS, WETH_ADDRESS, ethers.utils.parseEther("0.9"), false);
    expect((await dai.balanceOf(TEST2_ADDRESS)).toString()).to.equal("4214371005127484722905");
    console.log("Account 2 seized " + ethers.utils.formatUnits(await dai.balanceOf(TEST2_ADDRESS)) + " DAI");
  });

  it("kAAVE-receiveAToken-True", async function () {
    let tx;
    const TEST1_ADDRESS = await accounts[0].getAddress();
    const TEST2_ADDRESS = await accounts[1].getAddress();

    const kAAVEContract = await ethers.getContractFactory("KAAVE");
    const kAAVE = await kAAVEContract.deploy();
    await kAAVE.deployed();

    // deploy contract to return fake price to AaveOracle
    // fakePrice contract sets DAI/ETH to ~ 0.000213555 ETH or $0.49 as of 6/18/2021
    const fakePriceContract = await ethers.getContractFactory("fakePrice");
    const fakePrice = await fakePriceContract.deploy();
    await fakePrice.deployed();

    console.log("Impersonating DAI whale...");
    // impersonate DAI whale
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [DAI_WHALE_ADDRESS]
    }
    );
    const daiWhale = await ethers.provider.getSigner(DAI_WHALE_ADDRESS);
    const dai = new ethers.Contract(DAI_ADDRESS, daiABI, daiWhale);
    const weth = new ethers.Contract(WETH_ADDRESS, wethABI, accounts[0]);
    const adai = new ethers.Contract(ADAI_ADDRESS, atokenABI, accounts[1]);

    console.log("Using DAI whale to send 10000 DAI to test addresses...");
    await dai.push(TEST1_ADDRESS, ethers.utils.parseEther("10000"));
    await dai.push(TEST2_ADDRESS, ethers.utils.parseEther("2500"));
    expect(await dai.balanceOf(TEST1_ADDRESS)).to.equal((ethers.utils.parseEther("10000")).toString());
    expect(await dai.balanceOf(TEST2_ADDRESS)).to.equal((ethers.utils.parseEther("2500")).toString());

    console.log("Account 1 depositing 5000 DAI into kAAVE...");
    await dai.connect(accounts[0]).approve(kAAVE.address, ethers.utils.parseEther("5000"));
    await kAAVE.connect(accounts[0]).deposit(DAI_ADDRESS, ethers.utils.parseEther("5000"));

    console.log("Account 2 underwriting position with 50% additional buffer...")
    await dai.connect(accounts[1]).approve(kAAVE.address, ethers.utils.parseEther("2500"));
    await kAAVE.connect(accounts[1]).underwrite(DAI_ADDRESS, ethers.utils.parseEther("2500"));

    console.log("Account 1 borrows 0.9 ETH...");
    await kAAVE.connect(accounts[0]).borrow(WETH_ADDRESS, ethers.utils.parseEther("0.9"), 1);
    expect(await weth.balanceOf(TEST1_ADDRESS)).to.equal((ethers.utils.parseEther("0.9")).toString());

    console.log("Minting 3 WETH for Account 2...")
    await weth.connect(accounts[1]).deposit({ value: ethers.utils.parseEther("3") });
    expect(await weth.balanceOf(TEST2_ADDRESS)).to.equal((ethers.utils.parseEther("3")).toString());

    console.log("Account 2 attempting to call premptive liquidation...")
    await weth.connect(accounts[1]).approve(kAAVE.address, ethers.utils.parseEther("0.9"));
    await kAAVE.connect(accounts[1]).preempt(DAI_ADDRESS, WETH_ADDRESS, ethers.utils.parseEther("0.9"), false);

    console.log("Sending ETH from test account to oracle owner...");
    tx = await accounts[0].sendTransaction({
      to: ORACLE_OWNER_ADDRESS,
      value: ethers.utils.parseEther("3")
    });

    console.log("Grabbing oracle owner to impersonate...");
    // impersonate AAVE oracle owner
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ORACLE_OWNER_ADDRESS]
    });
    const oracleOwner = await ethers.provider.getSigner(ORACLE_OWNER_ADDRESS);

    let oraclePrice, debtInDAI;
    console.log("Fetching DAI/ETH price from oracle and calculating initial LTV...");
    const aaveOracle = new ethers.Contract(ORACLE_ADDRESS, OracleABI, oracleOwner);
    oraclePrice = await aaveOracle.getAssetPrice(DAI_ADDRESS);
    console.log("Initial DAI/ETH price: ", ethers.utils.formatUnits(oraclePrice));
    debtInDAI = (ethers.utils.parseEther("0.9")).div(oraclePrice);
    console.log("Initial debt in DAI: ", debtInDAI.toString());
    console.log("Initial LTV: ", Number(debtInDAI) / 5000);
    console.log("Initial LTV w/ buffer: ", Number(debtInDAI) / 7500);

    console.log("Taking control of oracle and modifying DAI/ETH price source...");
    await expect(aaveOracle.connect(oracleOwner).setAssetSources([DAI_ADDRESS], [fakePrice.address]))
      .to.emit(aaveOracle, 'AssetSourceUpdated')
      .withArgs(DAI_ADDRESS, fakePrice.address);
    oraclePrice = await aaveOracle.getAssetPrice(DAI_ADDRESS);
    console.log("Modified DAI/ETH price: ", ethers.utils.formatUnits(oraclePrice));
    debtInDAI = (ethers.utils.parseEther("0.9")).div(oraclePrice);
    console.log("Modified debt in DAI: ", debtInDAI.toString());
    console.log("Tasty LTV: ", Number(debtInDAI) / 5000);
    console.log("Tasty LTV w/ buffer: ", Number(debtInDAI) / 7500);

    console.log("kAAVE contract aDAI balance: ", ethers.utils.formatUnits(await adai.balanceOf(kAAVE.address)));
    console.log("Account 2 attempts to call preemptive liquidation now that LTV is within range...");
    await kAAVE.connect(accounts[1]).preempt(DAI_ADDRESS, WETH_ADDRESS, ethers.utils.parseEther("0.9"), true);
    expect((await adai.balanceOf(TEST2_ADDRESS)).toString()).to.equal("4214371005127484722905");
    console.log("Account 2 seized " + ethers.utils.formatUnits(await adai.balanceOf(TEST2_ADDRESS)) + " aDAI");
  });
});