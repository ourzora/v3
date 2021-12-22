import { HardhatUserConfig, task, types } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import 'tsconfig-paths/register';
import 'hardhat-gas-reporter';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-dependency-compiler';
import dotenv from 'dotenv';
import { deployZPM } from './scripts/deployZPM';
import { deployZMAM } from './scripts/deployZMAM';
import { deployTransferHelper } from './scripts/deployTransferHelper';
import { deployReserveAuctionV1 } from './scripts/deployReserveAuctionV1';
import { proposeModule } from './scripts/proposeModule';
import { deployAsksV1 } from './scripts/deployAsksV1';
import { deployOffersV1 } from './scripts/deployOffersV1';
import { deployCollectionOffersV1 } from './scripts/deployCollectionOffersV1';

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
  .addParam(
    'zoraV1Media',
    'ZORA V1 Media Address (for royalties)',
    undefined,
    types.string
  )
  .addParam(
    'zoraV1Market',
    'ZORA V1 Market Address (for royalties)',
    undefined,
    types.string
  )
  .addParam(
    'royaltyRegistry',
    'ZORA Collection Royalty Registry',
    undefined,
    types.string
  )
  .addParam(
    'protocolFeeSettings',
    'ZORA Protocol fee settings',
    undefined,
    types.string
  )
  .addParam('weth', 'WETH address', undefined, types.string)
  .setAction(deployReserveAuctionV1);

task('proposeModule', 'Propose a new module')
  .addParam(
    'moduleAddress',
    'Address of the module to approve',
    undefined,
    types.string
  )
  .setAction(proposeModule);

task('deployAsksV1', 'Deploy Asks V1')
  .addParam(
    'royaltyRegistry',
    'Manifold Royalty Registry',
    undefined,
    types.string
  )
  .addParam(
    'protocolFeeSettings',
    'ZORA Protocol fee settings',
    undefined,
    types.string
  )
  .addParam('weth', 'WETH address', undefined, types.string)
  .setAction(deployAsksV1);

task('deployOffersV1', 'Deploy Offers V1')
  .addParam(
    'royaltyRegistry',
    'Manifold Royalty Registry',
    undefined,
    types.string
  )
  .addParam('weth', 'WETH address', undefined, types.string)
  .setAction(deployOffersV1);

task('deployCollectionOffersV1', 'Deploy Collection Offers V1')
  .addParam(
    'royaltyRegistry',
    'Manifold Royalty Registry',
    undefined,
    types.string
  )
  .addParam(
    'protocolFeeSettings',
    'ZORA Protocol fee settings',
    undefined,
    types.string
  )
  .addParam('weth', 'WETH address', undefined, types.string)
  .setAction(deployCollectionOffersV1);

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.10',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 72,
    coinmarketcap: env ? (env.CMC_API_KEY as string) : '',
  },
  etherscan: {
    apiKey: env ? (env.ETHERSCAN_API_KEY as string) : '',
  },
  networks: {
    rinkeby: {
      accounts: env ? [`0x${env.RINKEBY_PRIVATE_KEY}`] : [],
      url: env ? env.RINKEBY_RPC_URL : '',
    },
    ropsten: {
      accounts: env ? [`0x${env.ROPSTEN_PRIVATE_KEY}`] : [],
      url: env ? env.ROPSTEN_RPC_URL : '',
    },
  },
  dependencyCompiler: {
    paths: [
      '@manifoldxyz/royalty-registry-solidity/contracts/RoyaltyEngineV1.sol',
    ],
  },
  typechain: {
    outDir: 'typechain',
  },
};

export default config;
