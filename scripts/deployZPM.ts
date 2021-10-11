import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export async function deployZPM(
  { registrarAddress }: { registrarAddress: string },
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    !addressBook.ZoraProposalManager,
    `ZoraProposalManager already present at ${addressPath}`
  );

  console.log(
    `Deploying ZPM from address ${await deployer.getAddress()} with registrar ${registrarAddress}`
  );
  const ZPMFactory = await hre.ethers.getContractFactory(
    'ZoraProposalManager',
    deployer
  );
  const proposalManager = await ZPMFactory.deploy(registrarAddress);
  console.log(
    `Deploying ZPM with tx ${proposalManager.deployTransaction.hash} to address ${proposalManager.address}`
  );
  await proposalManager.deployed();
  addressBook.ZoraProposalManager = proposalManager.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ZPM.`);
}
