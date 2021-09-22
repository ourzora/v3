import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-typechain';
import 'tsconfig-paths/register';
import 'hardhat-gas-reporter';
import dotenv from 'dotenv';

const env = dotenv.config().parsed;

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.5',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    currency: 'USD',
    coinmarketcap: env.CMC_API_KEY as string,
  },
};

export default config;
