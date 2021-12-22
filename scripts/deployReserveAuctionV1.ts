import { HardhatRuntimeEnvironment } from 'hardhat/types';
import * as fs from 'fs-extra';
import assert from 'assert';

export interface Args {
  zoraV1Media: string;
  zoraV1Market: string;
  royaltyRegistry: string;
  protocolFeeSettings: string;
  weth: string;
}

export async function deployReserveAuctionV1(
  {
    zoraV1Media,
    zoraV1Market,
    royaltyRegistry,
    protocolFeeSettings,
    weth,
  }: Args,
  hre: HardhatRuntimeEnvironment
) {
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

  console.log(
    `Deploying ReserveAuctionV1 from address ${await deployer.getAddress()}`
  );
  // @ts-ignore
  const ReserveAuctionFactory = await hre.ethers.getContractFactory(
    'ReserveAuctionV1'
  );
  const reserveAuction = await ReserveAuctionFactory.deploy(
    addressBook.ERC20TransferHelper,
    addressBook.ERC721TransferHelper,
    zoraV1Media,
    zoraV1Market,
    royaltyRegistry,
    protocolFeeSettings,
    // @ts-ignore
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
