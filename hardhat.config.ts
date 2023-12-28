import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-ethers";
import { HardhatUserConfig } from "hardhat/config";
import { existsSync, readFileSync } from 'fs';
import { chain, chainID } from "./constants";

const privKeyFile = '.private_key'
let privateKey = '';

if (existsSync(privKeyFile)) {
  privateKey = readFileSync(privKeyFile, "utf-8");
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    [chain.Ethereum]: {
      url: "https://ethereum.publicnode.com",
    },
    [chain.Arbitrum]: {
      url: "https://endpoints.omniatech.io/v1/arbitrum/one/public",
    },
    [chain.Avalanche]: {
      url: "https://endpoints.omniatech.io/v1/avax/mainnet/public",
    },
    [chain.Optimism]: {
      url: "https://endpoints.omniatech.io/v1/op/mainnet/public",
    },
    [chain.Base]: {
      url: "https://mainnet.base.org",
    },
    [chain.Polygon]: {
      url: "https://rpc-mainnet.maticvigil.com",
    },
    [chain.EthereumGoerli]: {
      url: "https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      gas: "auto",
      gasPrice: "auto",
    },
    [chain.AvalancheTestNet]: {
      url: "https://avalanche-fuji-c-chain.publicnode.com",
      gas: "auto",
      gasPrice: "auto",
    },
    [chain.ArbitrumGoerli]: {
      url: "https://endpoints.omniatech.io/v1/arbitrum/goerli/public",
      gas: "auto",
      gasPrice: "auto",
    },
    [chain.OptimismGoerli]: {
      url: "https://endpoints.omniatech.io/v1/op/goerli/public",
      gas: "auto",
      gasPrice: "auto",
    },
    [chain.BaseGoerli]: {
      url: "https://goerli.base.org",
      gas: "auto",
      gasPrice: "auto",
    },
  },

};

for (var net in config.networks) {
  if (net == 'hardhat') continue;

  config.networks[net]!.chainId = chainID[net as keyof typeof chainID];

  if (privateKey != '') {
    config.networks[net]!.accounts = [privateKey]
  }
}

export default config;
