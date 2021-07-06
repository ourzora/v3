import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-typechain';
import 'tsconfig-paths/register';

const config: HardhatUserConfig = {
  solidity: '0.8.5',
};

export default config;
