import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  royaltyRegistry: string;
  protocolFeeSettings: string;
  weth: string;
}

export async function deployCollectionOffersV1(
  { royaltyRegistry, protocolFeeSettings, weth }: Args,
  hre: HardhatRuntimeEnvironment
) {
  // @ts-ignore
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    addressBook.ERC20TransferHelper,
    `missing ERC20TransferHelper in ${addressPath}`
  );
  assert(
    addressBook.ERC721TransferHelper,
    `missing ERC721TransferHelper in ${addressPath}`
  );

  console.log(
    `Deploying CollectionOffersV1 from address ${await deployer.getAddress()}`
  );

  // @ts-ignore
  const CollectionOffersFactory = await hre.ethers.getContractFactory(
    'CollectionOffersV1'
  );
  const CollectionOffers = await CollectionOffersFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    royaltyRegistry,
    protocolFeeSettings,
    // @ts-ignore
    weth
  );
  console.log(
    `Deploying CollectionOffersV1 with tx ${CollectionOffers.deployTransaction.hash} to address ${CollectionOffers.address}`
  );

  await CollectionOffers.deployed();
  addressBook.CollectionOffersV1 = CollectionOffers.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed CollectionOffersV1`);
}
