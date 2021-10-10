import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';
import { ZoraProposalManager } from '../typechain';

interface Args {
  moduleAddress: string;
}

export async function proposeModule(
  { moduleAddress }: Args,
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    addressBook.ZoraProposalManager,
    `Could not find ZoraProposalManager at ${addressPath}, deploy it first!`
  );

  const ZPMFactory = await hre.ethers.getContractFactory(
    'ZoraProposalManager',
    deployer
  );
  const proposalManager = ZPMFactory.connect(deployer).attach(
    addressBook.ZoraProposalManager
  ) as ZoraProposalManager;

  console.log(`Proposing module ${moduleAddress}`);
  const tx = await proposalManager.proposeModule(moduleAddress);
  console.log(`Proposal TX: ${tx.hash}`);
  await tx.wait();
  console.log(`Proposal Confirmed.`);
}
