import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';

export interface Args {
  owner: string;
}

export async function deployOffersV1(
  { owner }: Args,
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  const FeeSettingsFactory = await hre.ethers.getContractFactory(
    'ZoraProtocolFeeSettingsV1'
  );
  const feeSettings = await FeeSettingsFactory.deploy(owner);
  console.log(
    `Deploying ZoraProtocolFeeSettingsV1 with tx ${feeSettings.deployTransaction.hash} to address ${feeSettings.address}`
  );

  await feeSettings.deployed();

  addressBook.ZoraProtocolFeeSettingsV1 = feeSettings.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ZoraProtocolFeeSettingsV1`);
}
