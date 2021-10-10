import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  weth: string;
  zoraV1Media: string;
}

export async function deployReserveAuctionV1(
  { weth, zoraV1Media }: Args,
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

  console.log(
    `Deploying ReserveAuctionV1 from address ${await deployer.getAddress()}`
  );
  const ReserveAuctionFactory = await hre.ethers.getContractFactory(
    'ReserveAuctionV1'
  );
  const reserveAuction = await ReserveAuctionFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    zoraV1Media,
    weth
  );
  console.log(
    `Deploying ReserveAuctionV1 with tx ${reserveAuction.deployTransaction.hash} to address ${reserveAuction.address}`
  );
  await reserveAuction.deployed();
  addressBook.ReserveAuctionV1 = reserveAuction.address;
  await fs.writeFile(addressPath, JSON.stringify(addressBook, null, 2));
  console.log(`Deployed ReserveAuctionV1`);
}
