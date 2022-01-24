import { HardhatUserConfig, task, types } from 'hardhat/config';
import '@nomiclabs/hardhat-ethers';
import '@typechain/hardhat';
import 'tsconfig-paths/register';
import 'hardhat-gas-reporter';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-dependency-compiler';
import dotenv from 'dotenv';
import { deployZMM } from './scripts/deployZMM';
import { deployTransferHelper } from './scripts/deployTransferHelper';
import { deployReserveAuctionV1 } from './scripts/deployReserveAuctionV1';
import { deployAsksV1 } from './scripts/deployAsksV1';
import { deployAsksV1_1 } from './scripts/deployAsksV1_1';
import { deployOffersV1 } from './scripts/deployOffersV1';
import { deployCollectionOffersV1 } from './scripts/deployCollectionOffersV1';
import { deployCoveredCallsV1 } from './scripts/deployCoveredCallsV1';
import { deployProtocolFeeSettings } from './scripts/deployProtocolFeeSettings';
import { deployCoveredPutsV1 } from './scripts/deployCoveredPutsV1';

const env = dotenv.config().parsed;

task(
  'deployProtocolFeeSettings',
  'Deploy Zora Protocol Fee Settings'
).setAction(deployProtocolFeeSettings);

task('deployZMM', 'Deploy Zora Module Manager')
  .addParam(
    'registrarAddress',
    'Address to use for registering proposals',
    undefined,
    types.string
  )
  .setAction(deployZMM);

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
  .setAction(deployReserveAuctionV1);

task('deployAsksV1', 'Deploy Asks V1').setAction(deployAsksV1);

task('deployAsksV1_1', 'Deploy Asks V1.1').setAction(deployAsksV1_1);

task('deployOffersV1', 'Deploy Offers V1')
  .addParam(
    'royaltyRegistry',
    'Manifold Royalty Registry',
    undefined,
    types.string
  )
  .addParam('weth', 'WETH address', undefined, types.string)
  .setAction(deployOffersV1);

task('deployCollectionOffersV1', 'Deploy Collection Offers V1').setAction(
  deployCollectionOffersV1
);

task('deployCoveredCallsV1', 'Deploy Covered Calls V1').setAction(
  deployCoveredCallsV1
);

task('deployCoveredPutsV1', 'Deploy Covered Puts V1').setAction(
  deployCoveredPutsV1
);

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.10',
    settings: {
      optimizer: {
        enabled: true,
        runs: 500000,
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
    mainnet: {
      accounts: env ? [`0x${env.MAINNET_PRIVATE_KEY}`] : [],
      url: env ? env.MAINNET_RPC_URL : '',
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
