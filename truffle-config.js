require("dotenv").config();

const HDWalletProvider = require("@truffle/hdwallet-provider");

module.exports = {
  contracts_directory: "./contracts",
  networks: {
    development: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "*",
      gasPrice: 15000000000,
    },
    bsc_testnet: {
      networkCheckTimeout: 100000000,
      provider: () =>
        new HDWalletProvider(
          process.env.PRIVATE_KEY,
          `https://data-seed-prebsc-1-s1.binance.org:8545`
        ),
      network_id: 97,
      confirmations: 0,
      timeoutBlocks: 2000000,
      skipDryRun: true,
    },
    rinkeby: {
      networkCheckTimeoutnetworkCheckTimeout: 100000,
      provider: () =>
        new HDWalletProvider(
          process.env.PRIVATE_KEY,
          `wss://rinkeby.infura.io/ws/v3/ You api key here`
        ),
      network_id: 4,
      confirmations: 0,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
    testnet: {
      networkCheckTimeoutnetworkCheckTimeout: 100000,
      provider: () =>
        new HDWalletProvider(
          process.env.PRIVATE_KEY,
          `https://xapi.testnet.fantom.network/lachesis`
        ),
      network_id: 0xfa2,
      confirmations: 0,
      timeoutBlocks: 200,
      skipDryRun: true,
    },
    mainnet: {
      provider: () =>
        new HDWalletProvider(process.env.PRIVATE_KEY, `https://rpc.ftm.tools/`),
      network_id: 250,
      confirmations: 5,
      timeoutBlocks: 100,
      skipDryRun: true,
    },
  },
  plugins: ["truffle-contract-size", "truffle-plugin-verify"],
  api_keys: {
    ftmscan: process.env.FTMSCAN_API_KEY,
    etherscan: process.env.ETHERSCAN_API_KEY,
    bscscan: process.env.BSC_API_KEY,
  },
  compilers: {
    solc: {
      version: "0.6.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 1000000,
        },
        evmVersion: "berlin",
      },
    },
  },
};
