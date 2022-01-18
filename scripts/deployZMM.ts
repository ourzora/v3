import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export async function deployZMM(
  {
    registrarAddress,
  }: { registrarAddress: string; moduleFeeTokenAddress: string },
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    !addressBook.ZoraModuleManager,
    `ZoraModuleManager already present at ${addressPath}`
  );
  assert(
    !!addressBook.ZoraProtocolFeeSettings,
    `ZoraProtocolFeeSettings not found at ${addressPath}`
  );

  console.log(
    `Deploying ZMM from address ${await deployer.getAddress()} with registrar ${registrarAddress}`
  );
  const ZMMFactory = await hre.ethers.getContractFactory(
    'ZoraModuleManager',
    deployer
  );
  const moduleManager = await ZMMFactory.deploy(
    registrarAddress,
    addressBook.ZoraProtocolFeeSettings
  );
  console.log(
    `Deploying ZMM with tx ${moduleManager.deployTransaction.hash} to address ${moduleManager.address}`
  );
  await moduleManager.deployed();
  addressBook.ZoraModuleManager = moduleManager.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ZMM.`);
}
