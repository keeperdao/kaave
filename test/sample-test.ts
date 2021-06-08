import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";

describe("Token", function() {
  let accounts: Signer[];

  beforeEach(async function () {
    accounts = await ethers.getSigners();
  });
  
  it("Should return the new greeting once it's changed", async function() {
    const Greeter = await ethers.getContractFactory("Greeter");
    const greeter = await Greeter.deploy("Hello, world!");
    
    await greeter.deployed();
    expect(await greeter.greet()).to.equal("Hello, world!");

    await greeter.setGreeting("Hola, mundo!");
    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
});