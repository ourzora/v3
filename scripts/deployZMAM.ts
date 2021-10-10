import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export async function deployZMAM(_, hre: HardhatRuntimeEnvironment) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    addressBook.ZoraProposalManager,
    `Could not find ZoraProposalManager at ${addressPath}, deploy it first!`
  );
  assert(
    !addressBook.ZoraModuleApprovalsManager,
    `ZoraModuleApprovalsManager already present at ${addressPath}`
  );

  console.log(
    `Deploying ZMAM from address ${await deployer.getAddress()} with proposal manager ${
      addressBook.ZoraProposalManager
    }`
  );
  const ZMAMFactory = await hre.ethers.getContractFactory(
    'ZoraModuleApprovalsManager',
    deployer
  );
  const zmam = await ZMAMFactory.deploy(addressBook.ZoraProposalManager);
  console.log(
    `Deploying ZMAM with tx ${zmam.deployTransaction.hash} to address ${zmam.address}`
  );
  await zmam.deployed();
  addressBook.ZoraModuleApprovalsManager = zmam.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ZMAM.`);
}
