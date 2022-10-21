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

const okc_mainnet_rpc = 'https://exchainrpc.okex.org';
const network_okc_mainnet = {
  provider: () => new HDWalletProvider(privateKey, okc_mainnet_rpc),
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

const gnosis_mainnet_rpc = 'https://rpc.xdaichain.com';
const network_gnosis_mainnet = {
  provider: () => new HDWalletProvider(privateKey, gnosis_mainnet_rpc),
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

const optimism_testnet_rpc = 'https://kovan.optimism.io';
const network_optimism_testnet = {
  provider: () => new HDWalletProvider(privateKey, optimism_testnet_rpc),
  network_id: 69,
  gas: 10 * 10000,
  gasPrice: 0.00001 * 10**9,
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

const fantom_testnet_rpc = 'https://rpc.testnet.fantom.network/';
const network_fantom_testnet = {
  provider: () => new HDWalletProvider(privateKey, fantom_testnet_rpc),
  network_id: 4002,
  gas: 600 * 10000,
  gasPrice: 355 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const cube_mainnet_rpc = 'https://http-mainnet.cube.network';
const network_cube_mainnet = {
  provider: () => new HDWalletProvider(privateKey, cube_mainnet_rpc),
  network_id: 1818,
  gas: 40 * 10000,
  gasPrice: 200 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const cube_testnet_rpc = 'https://http-testnet.cube.network';
const network_cube_testnet = {
  provider: () => new HDWalletProvider(privateKey, cube_testnet_rpc),
  network_id: 1819,
  gas: 500 * 10000,
  gasPrice: 1 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false
};

const metis_mainnet_rpc = 'https://andromeda.metis.io/?owner=1088';
const network_metis_mainnet = {
  provider: () => new HDWalletProvider(privateKey, metis_mainnet_rpc),
  network_id: 1088,
  gas: 500 * 10000,
  gasPrice: 20 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false,
};

const celo_mainnet_rpc = 'https://forno.celo.org';
const network_celo_mainnet = {
  provider: () => new HDWalletProvider(privateKey, celo_mainnet_rpc),
  network_id: 42220,
  gas: 400 * 10000,
  gasPrice: 0.2 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false,
};

const celo_testnet_rpc = 'https://alfajores-forno.celo-testnet.org';
const network_celo_testnet = {
  provider: () => new HDWalletProvider(privateKey, celo_testnet_rpc),
  network_id: 44787,
  gas: 500 * 10000,
  gasPrice: 0.2 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false,
};

const kcc_mainnet_rpc = 'https://rpc-mainnet.kcc.network';
const network_kcc_mainnet = {
  provider: () => new HDWalletProvider(privateKey, kcc_mainnet_rpc),
  network_id: 321,
  gas: 50 * 10000,
  gasPrice: 1.5 * 10**9,
  confirmations: 0,
  timeoutBlocks: 200,
  skipDryRun: false,
};

const network_development = {
  host: "127.0.0.1",
  port: 18545,
  network_id: "*",
 };

 module.exports = {
  networks: {
    eth: network_eth_mainnet,
    bsc: network_bsc_mainnet,
    heco: network_heco_mainnet,
    arbitrum: network_arbitrum_mainnet,
    polygon: network_polygon_mainnet,
    gnosis: network_gnosis_mainnet,
    fantom: network_fantom_mainnet,
    avalanche: network_avalanche_mainnet,
    optimism: network_optimism_mainnet,
    okc: network_okc_mainnet,
    cube: network_cube_mainnet,
    metis: network_metis_mainnet,
    celo: network_celo_mainnet,
    kcc: network_kcc_mainnet,

    eth_ropsten: network_eth_ropsten,
    bsc_testnet: network_bsc_testnet,
    arbitrum_rinkeby: network_arbitrum_rinkeby,
    fantom_testnet: network_fantom_testnet,
    optimism_testnet: network_optimism_testnet,
    cube_testnet: network_cube_testnet,
    celo_testnet: network_celo_testnet,

    development: network_development,
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
      version: "0.8.15",
      settings: {
       optimizer: {
         enabled: true,
         runs: 999999
       },
      }
    }
  },

  db: {
    enabled: false
  }
};
