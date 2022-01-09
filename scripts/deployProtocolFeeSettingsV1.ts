import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';

export async function deployProtocolFeeSettingsV1(
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  const FeeSettingsFactory = await hre.ethers.getContractFactory(
    'ZoraProtocolFeeSettings'
  );
  const feeSettings = await FeeSettingsFactory.deploy();
  console.log(
    `Deploying ZoraProtocolFeeSettings with tx ${feeSettings.deployTransaction.hash} to address ${feeSettings.address}`
  );

  await feeSettings.deployed();

  addressBook.ZoraProtocolFeeSettings = feeSettings.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ZoraProtocolFeeSettings`);
}
