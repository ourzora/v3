import { HardhatRuntimeEnvironment } from 'hardhat/types';
import assert = require('assert');
import * as fs from 'fs-extra';

interface TaskArgs {
  transferType: string;
}

export async function deployTransferHelper(
  { transferType }: TaskArgs,
  hre: HardhatRuntimeEnvironment
) {
  const [deployer] = await hre.ethers.getSigners();
  const { chainId } = await deployer.provider.getNetwork();

  const addressPath = `${process.cwd()}/addresses/${chainId}.json`;
  const addressBook = JSON.parse(await fs.readFileSync(addressPath));

  assert(
    ['ERC20', 'ERC721', 'ERC1155'].includes(transferType),
    `unknown transfer type ${transferType}`
  );
  assert(
    addressBook.ZoraModuleApprovalsManager,
    `Could not find ZoraModuleApprovalsManager at ${addressPath}, deploy it first!`
  );
  assert(
    !addressBook[`${transferType}TransferHelper`],
    `${transferType}TransferHelper already present at ${addressPath}`
  );

  console.log(
    `Deploying ${transferType} transfer helper from address ${await deployer.getAddress()}`
  );
  const Factory = await hre.ethers.getContractFactory(
    `${transferType}TransferHelper`,
    deployer
  );
  const helper = await Factory.deploy(addressBook.ZoraModuleApprovalsManager);
  console.log(
    `Deploying transfer helper with tx ${helper.deployTransaction.hash} to address ${helper.address}`
  );
  await helper.deployed();
  addressBook[`${transferType}TransferHelper`] = helper.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ${transferType} transfer helper.`);
}
