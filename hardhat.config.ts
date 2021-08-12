import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-typechain';
import 'tsconfig-paths/register';

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
};

export default config;
