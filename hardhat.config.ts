import { HardhatUserConfig, task, types } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-typechain';
import 'tsconfig-paths/register';
import 'hardhat-gas-reporter';
import dotenv from 'dotenv';
import { deployZPM } from './scripts/deployZPM';
import { deployZMAM } from './scripts/deployZMAM';
import { deployTransferHelper } from './scripts/deployTransferHelper';
import { deployReserveAuctionV1 } from './scripts/deployReserveAuctionV1';
import { proposeModule } from './scripts/proposeModule';

const env = dotenv.config().parsed;

task('deployZPM', 'Deploy Zora Proposal Manager')
  .addParam(
    'registrarAddress',
    'Address to use for registering proposals',
    undefined,
    types.string
  )
  .setAction(deployZPM);

task('deployZMAM', 'Deploy Zora Module Approvals Manager').setAction(
  deployZMAM
);

task('deployTransferHelper', 'Deploy A Transfer Helper')
  .addParam(
    'transferType',
    'One of ERC20, ERC721, ERC1155',
    undefined,
    types.string
  )
  .setAction(deployTransferHelper);

task('deployReserveAuctionV1', 'Deploy Reserve Auction V1')
  .addParam('weth', 'WETH address', undefined, types.string)
  .addParam(
    'zoraV1Media',
    'Zora V1 Media Address (for royalties)',
    undefined,
    types.string
  )
  .setAction(deployReserveAuctionV1);

task('proposeModule', 'Propose a new module')
  .addParam(
    'moduleAddress',
    'Address of the module to approve',
    undefined,
    types.string
  )
  .setAction(proposeModule);

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
    coinmarketcap: env ? (env.CMC_API_KEY as string) : '',
  },
  networks: {
    rinkeby: {
      accounts: env ? [`0x${env.RINKEBY_PRIVATE_KEY}`] : [],
      url: env ? env.RINKEBY_RPC_URL : '',
    },
  },
};

export default config;
