const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');
const Web3 = require("web3");

const privateKey = fs.readFileSync('./.private_key', {encoding: 'utf8', flag: 'r' });

const eth_mainnet_rpc = 'https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161';
const network_eth_mainnet = {
  provider: () => new HDWalletProvider(privateKey, eth_mainnet_rpc),
  network_id: 1,
  gas: 80 * 10000,
  gasPrice: 100 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const eth_ropsten_rpc = 'https://ropsten.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161';
const network_eth_ropsten = {
    provider: () => new HDWalletProvider(privateKey, eth_ropsten_rpc),
    network_id: 3,
    gas: 20 * 10000,
    gasPrice: 6 * 10**9,
    confirmations: 0,
    timeoutBlocks: 200,
    skipDryRun: false
};

const bsc_mainnet_rpc = 'https://bsc-dataseed.binance.org';
const network_bsc_mainnet = {
  provider: () => new HDWalletProvider(privateKey, bsc_mainnet_rpc),
  network_id: 56,
  gas: 150 * 10000,
  gasPrice: 5 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const bsc_testnet_rpc = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const network_bsc_testnet = {
  provider: () => new HDWalletProvider(privateKey, bsc_testnet_rpc),
  network_id: 97,
  gas: 30 * 10000,
  gasPrice: 10 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const heco_mainnet_rpc = 'https://http-mainnet.hecochain.com';
const network_heco_mainnet = {
  provider: () => new HDWalletProvider(privateKey, heco_mainnet_rpc),
  network_id: 128,
  gas: 150 * 10000,
  gasPrice: 3 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const heco_testnet_rpc = 'https://http-testnet.hecochain.com';
const network_heco_testnet = {
  provider: () => new HDWalletProvider(privateKey, heco_testnet_rpc),
  network_id: 256,
  gas: 150 * 10000,
  gasPrice: 3 * 10**9,
  confirmations: 1,
  timeoutBlocks: 200,
  skipDryRun: false
};

const polygon_mainnet_rpc = 'https://rpc-mainnet.maticvigil.com';
const network_polygon_mainnet = {
  provider: () => new HDWalletProvider(privateKey, polygon_mainnet_rpc),
  network_id: 137,
  gas: 150 * 10000,
  gasPrice: 50 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const arbitrum_mainnet_rpc = 'https://arb1.arbitrum.io/rpc';
const network_arbitrum_mainnet = {
  provider: () => new HDWalletProvider(privateKey, arbitrum_mainnet_rpc),
  network_id: 42161,
  gas: 5000 * 10000,
  gasPrice: 2 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const arbitrum_rinkeby_rpc = 'https://rinkeby.arbitrum.io/rpc';
const network_arbitrum_rinkeby = {
  provider: () => new HDWalletProvider(privateKey, arbitrum_rinkeby_rpc),
  network_id: 421611,
  gas: 5000 * 10000,
  gasPrice: 2 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const oec_mainnet_rpc = 'https://exchainrpc.okex.org';
const network_oec_mainnet = {
  provider: () => new HDWalletProvider(privateKey, oec_mainnet_rpc),
  network_id: 66,
  gas: 220 * 10000,
  gasPrice: 1 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const network_avalanche_mainnet = {
  provider: () => {
    return new HDWalletProvider({
      privateKeys: [privateKey],
      providerOrUrl: new Web3.providers.HttpProvider(
        'https://api.avax.network/ext/bc/C/rpc'
      ),
    });
  },
  network_id: "*",
  gas: 150 * 10000,
  gasPrice: 40 * 10**9,
};

const xdai_mainnet_rpc = 'https://rpc.xdaichain.com';
const network_xdai_mainnet = {
  provider: () => new HDWalletProvider(privateKey, xdai_mainnet_rpc),
  network_id: 100,
  gas: 150 * 10000,
  gasPrice: 22 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const optimism_mainnet_rpc = 'https://mainnet.optimism.io';
const network_optimism_mainnet = {
  provider: () => new HDWalletProvider(privateKey, optimism_mainnet_rpc),
  network_id: 10,
  gas: 150 * 10000,
  gasPrice: 1 * 10**6,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const fantom_mainnet_rpc = 'https://rpc.ftm.tools';
const network_fantom_mainnet = {
  provider: () => new HDWalletProvider(privateKey, fantom_mainnet_rpc),
  network_id: 250,
  gas: 150 * 10000,
  gasPrice: 150 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const network_development = {
  host: "127.0.0.1",
  port: 18545,
  network_id: "*",
 };

 module.exports = {
  networks: {
    eth_ropsten: network_eth_ropsten,
    bsc_testnet: network_bsc_testnet,
    arbitrum_rinkeby: network_arbitrum_rinkeby,
  },

  mocha: {
    // timeout: 100000
  },

  api_keys: {
    etherscan: '',
    bscscan: '',
    hecoinfo: '',
    ftmscan: '',
    polygonscan: '',
    snowtrace: '',
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.8",
      settings: {
       optimizer: {
         enabled: true,
         runs: 200
       },
       evmVersion: "istanbul"
      }
    }
  },

  db: {
    enabled: false
  }
};
