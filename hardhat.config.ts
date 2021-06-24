import "dotenv/config";
import "@nomiclabs/hardhat-waffle";
import { task, HardhatUserConfig } from "hardhat/config";
import "solidity-coverage";
import "hardhat-typechain";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-gas-reporter";
import "hardhat-deploy";
require('dotenv').config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 let account, referal, bot, kovan, mainnet, ropsten, goerli;

kovan = process.env['kovan']
mainnet = process.env['mainnet']
referal = process.env['REF']


module.exports = {

  solidity: {
    version: "0.7.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {

    localhost: {
      url: 'http://127.0.0.1:8545',
      // accounts: [
      //      account,
      //      referal
      //  ],
      gas: 12000000,
      blockGasLimit: 12000000
    },

    hardhat: {
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
        accountsBalance: '10000000000000000000000000000000',
      },
      forking: {
        url: mainnet,
        blockNumber: 12522000,
      },
    },
    kovan: {
      url: kovan,
      accounts: [
        referal
      ],
    }
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY as string
  },
  mocha: {
    timeout: 60000
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    coinmarketcap: process.env.CMC_API_KEY,
  }
};
