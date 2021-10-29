import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  royaltyRegistry: string;
  weth: string;
}

export async function deployAsksV1(
  { royaltyRegistry, weth }: Args,
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

  console.log(`Deploying AsksV1 from address ${await deployer.getAddress()}`);

  const AsksFactory = await hre.ethers.getContractFactory('AsksV1');
  const asks = await AsksFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    royaltyRegistry,
    weth
  );
  console.log(
    `Deploying AsksV1 with tx ${asks.deployTransaction.hash} to address ${asks.address}`
  );

  await asks.deployed();
  addressBook.AsksV1 = asks.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed AsksV1`);
}
