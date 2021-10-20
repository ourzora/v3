import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';

export async function deployRoyaltyRegistryV1(hre: HardhatRuntimeEnvironment) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  console.log(
    `Deploying CollectionRoyaltyRegistryV1 from address ${await deployer.getAddress()}`
  );

  const RoyaltyRegistryFactory = await hre.ethers.getContractFactory(
    'CollectionRoyaltyRegistryV1'
  );
  const royaltyRegistry = await RoyaltyRegistryFactory.deploy();

  console.log(
    `Deploying CollectionRoyaltyRegistryV1 with tx ${royaltyRegistry.deployTransaction.hash} to address ${royaltyRegistry.address}`
  );

  await royaltyRegistry.deployed();
  addressBook.AsksV1 = royaltyRegistry.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed CollectionRoyaltyRegistryV1`);
}
