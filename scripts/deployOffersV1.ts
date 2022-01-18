import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  zoraV1Media: string;
  royaltyRegistry: string;
  protocolFeeSettings: string;
  weth: string;
}

export async function deployOffersV1(
  { royaltyRegistry, protocolFeeSettings, weth }: Args,
  hre: HardhatRuntimeEnvironment
) {
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

  console.log(`Deploying OffersV1 from address ${await deployer.getAddress()}`);

  const OffersFactory = await hre.ethers.getContractFactory('OffersV1');
  const offers = await OffersFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    royaltyRegistry,
    protocolFeeSettings,
    // @ts-ignore
    weth
  );
  console.log(
    `Deploying OffersV1 with tx ${offers.deployTransaction.hash} to address ${offers.address}`
  );

  await offers.deployed();
  addressBook.OffersV1 = offers.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed OffersV1`);
}
