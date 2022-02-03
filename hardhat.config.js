// hardhat.config.js
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
// require("@nomiclabs/hardhat-solpp");
const {
  mnemonic, test1, test2, etherScan, mnemonicTest
} = require("./secrets.json");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  // solidity: "0.6.12",
  // solidity: "0.5.16",
  solidity: "0.8.10",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  mocha: {
    timeout: 50000
  },
  etherscan: {
    apiKey: etherScan,
  },
  defaultNetwork: "bsctestnet",
  networks: {
    bscmainnet: {
      url: "https://speedy-nodes-nyc.moralis.io/81e9989bff9efaefa71d2072/bsc/mainnet",
      chainId: 56,
      gasPrice: 5000000000,
      accounts: {
        mnemonic
      }
    },
    bsctestnet: {
      url: "http://127.0.0.1:8545",
      chainId: 56,
      gasPrice: 5000000000,
      accounts: { mnemonic }
    }
  }
};