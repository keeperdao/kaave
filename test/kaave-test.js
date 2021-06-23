import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("Token", function () {
    let accounts: Signer[];
  
    beforeEach(async function () {
      accounts = await ethers.getSigners();

      const KAave = await ethers.getContractFactory("KAave");
      const kaave = KAave.deploy();
    });
    
    it("Should return the new greeting once it's changed", async function() {
      
    });
  });