import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export async function deployCoveredPutsV1(_, hre: HardhatRuntimeEnvironment) {
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
  assert(
    addressBook.ZoraProtocolFeeSettings,
    `missing ZoraProtocolFeeSettings in ${addressPath}`
  );
  assert(addressBook.WETH, `missing WETH in ${addressPath}`);
  assert(
    addressBook.RoyaltyEngineV1,
    `missing RoyaltyEngineV1 in ${addressPath}`
  );

  console.log(
    `Deploying CoveredPutsV1 from address ${await deployer.getAddress()}`
  );

  // @ts-ignore
  const CoveredPutsFactory = await hre.ethers.getContractFactory(
    'CoveredPutsV1'
  );
  const CoveredPuts = await CoveredPutsFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    addressBook.RoyaltyEngineV1,
    addressBook.ZoraProtocolFeeSettings,
    addressBook.WETH
  );
  console.log(
    `Deploying CoveredPutsV1 with tx ${CoveredPuts.deployTransaction.hash} to address ${CoveredPuts.address}`
  );

  await CoveredPuts.deployed();
  addressBook.CoveredPutsV1 = CoveredPuts.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed CoveredPutsV1`);
}
