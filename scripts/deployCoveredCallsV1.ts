import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  royaltyRegistry: string;
  weth: string;
}

export async function deployCoveredCallsV1(
  { royaltyRegistry, weth }: Args,
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
    `Deploying CoveredCallsV1 from address ${await deployer.getAddress()}`
  );

  // @ts-ignore
  const CollectionOffersFactory = await hre.ethers.getContractFactory(
    'CoveredCallsV1'
  );
  const CoveredCalls = await CollectionOffersFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    royaltyRegistry,
    weth
  );
  console.log(
    `Deploying CoveredCallsV1 with tx ${CoveredCalls.deployTransaction.hash} to address ${CoveredCalls.address}`
  );

  await CoveredCalls.deployed();
  addressBook.CoveredCallsV1 = CoveredCalls.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed CoveredCallsV1`);
}
