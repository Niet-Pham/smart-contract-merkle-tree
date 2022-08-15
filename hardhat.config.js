require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("@nomiclabs/hardhat-solhint");

const BSC_API_KEY = process.env.BSC_API_KEY;
const BSC_PROVIDER = process.env.BSC_PROVIDER;
const BSC_TESTNET_PROVIDER = process.env.BSC_TESTNET_PROVIDER;
const GAS_PRICE = 5;
const GAS_UNIT = 10 ** 9; // Gwei
const COINMARKETCAP_API_KEY = process.env.COINMARKETCAP_API_KEY ? process.env.COINMARKETCAP_API_KEY : ""
const REPORT_GAS = COINMARKETCAP_API_KEY !== ""

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    bsctestnet: {
      url: BSC_TESTNET_PROVIDER,
      chainId: 97,
      gas: 8000000,
      accounts: [process.env.PRIVATE_KEY]  // if using private key to deploy change { mnemonic: MNEMONIC } => your private key
    },
    bscmainnet: {
      url: BSC_PROVIDER,
      chainId: 56,
      gas: 8000000,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: BSC_API_KEY
  },
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  mocha: {
    timeout: 180000
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: true,
    runOnCompile: false,
    strict: false,
  },
  gasReporter: {
    enabled: REPORT_GAS,
    currency: 'USD',
    gasPrice: GAS_PRICE,
    showMethodSig: false,
    token: "BNB",
    coinmarketcap: COINMARKETCAP_API_KEY
  }
};
