import { ethers } from 'hardhat';
import {
  BadErc721,
  BaseModuleProxy,
  ReserveAuctionProxy,
  ReserveAuctionV1,
  TestEip2981Erc721,
  TestErc721,
  TestModuleProxy,
  TestModuleV1,
  Weth,
} from '../typechain';
import { BigNumber, BigNumberish, Contract } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';
import {
  Erc721,
  MarketFactory,
  Media,
  MediaFactory,
} from '@zoralabs/core/dist/typechain';

export const revert = (messages: TemplateStringsArray, ...rest) =>
  `VM Exception while processing transaction: reverted with reason string '${messages[0]}'`;

export const ONE_ETH = ethers.utils.parseEther('1');
export const TWO_ETH = ethers.utils.parseEther('2');
export const TENTH_ETH = ethers.utils.parseEther('0.1');
export const THOUSANDTH_ETH = ethers.utils.parseEther('0.001');

// Helper function to parse numbers and do approximate number calculations
export const toRoundedNumber = (bn: BigNumber) =>
  bn.div(THOUSANDTH_ETH).toNumber();

export const deployBaseModuleProxy = async () => {
  const BaseModuleProxyFactory = await ethers.getContractFactory(
    'BaseModuleProxy'
  );
  const baseModuleProxy = await BaseModuleProxyFactory.deploy();
  await baseModuleProxy.deployed();
  return baseModuleProxy as BaseModuleProxy;
};

export const deployTestModuleProxy = async () => {
  const TestModuleProxyFactory = await ethers.getContractFactory(
    'TestModuleProxy'
  );
  const testModuleProxy = await TestModuleProxyFactory.deploy();
  await testModuleProxy.deployed();
  return testModuleProxy as TestModuleProxy;
};

export const deployTestModule = async () => {
  const TestModuleFactory = await ethers.getContractFactory('TestModuleV1');
  const testModule = await TestModuleFactory.deploy();
  await testModule.deployed();
  return testModule as TestModuleV1;
};

export const deployZoraProtocol = async () => {
  const [deployer] = await ethers.getSigners();
  const market = await (await new MarketFactory(deployer).deploy()).deployed();
  const media = await (
    await new MediaFactory(deployer).deploy(market.address)
  ).deployed();
  await market.configure(media.address);
  return { market, media };
};

export const deployBadERC721 = async () => {
  const BadERC721Factory = await ethers.getContractFactory('BadERC721');
  const badERC721 = await BadERC721Factory.deploy();
  return badERC721 as BadErc721;
};

export const deployTestERC271 = async () => {
  const TestERC721Factory = await ethers.getContractFactory('TestERC721');
  const testERC721 = await TestERC721Factory.deploy();
  return testERC721 as TestErc721;
};

export const deployTestEIP2981ERC721 = async () => {
  const TestEIP2981ERC721Factory = await ethers.getContractFactory(
    'TestEIP2981ERC721'
  );
  const testEIP2981ERC721 = await TestEIP2981ERC721Factory.deploy();
  return testEIP2981ERC721 as TestEip2981Erc721;
};

export const deployWETH = async () => {
  const WETHFactory = await ethers.getContractFactory('WETH');
  const weth = await WETHFactory.deploy();
  return weth as Weth;
};

export const deployReserveAuctionProxy = async () => {
  const ReserveAuctionProxyFactory = await ethers.getContractFactory(
    'ReserveAuctionProxy'
  );
  const reserveAuctionProxy = await ReserveAuctionProxyFactory.deploy();
  await reserveAuctionProxy.deployed();
  return reserveAuctionProxy as ReserveAuctionProxy;
};

export const deployReserveAuctionV1 = async () => {
  const ReserveAuctionV1Factory = await ethers.getContractFactory(
    'ReserveAuctionV1'
  );
  const reserveAuction = await ReserveAuctionV1Factory.deploy();
  await reserveAuction.deployed();
  return reserveAuction as ReserveAuctionV1;
};

export const connectAs = async <T extends unknown>(
  proxy: Contract,
  moduleName: string
) => {
  const Factory = await ethers.getContractFactory(moduleName);
  return Factory.attach(proxy.address) as T;
};

export const registerVersion = async (
  proxy: BaseModuleProxy,
  moduleAddress: string,
  callData: BytesLike = []
) => {
  await proxy.registerVersion(moduleAddress, callData);
};

export const mintZoraNFT = async (zoraV1Media: Media, seed = '') => {
  const metadataHex = ethers.utils.formatBytes32String(seed);
  const metadataHash = ethers.utils.sha256(metadataHex);
  const hash = ethers.utils.arrayify(metadataHash);
  await zoraV1Media.mint(
    {
      tokenURI: 'zora.co',
      metadataURI: 'zora.co',
      contentHash: hash,
      metadataHash: hash,
    },
    {
      prevOwner: { value: 0 },
      owner: { value: BigNumber.from('85000000000000000000') },
      creator: { value: BigNumber.from('15000000000000000000') },
    }
  );
};

export const approveNFTTransfer = async (
  token: Erc721,
  spender: string,
  tokenId: string = '0'
) => {
  await token.approve(spender, tokenId);
};

export async function createReserveAuction(
  tokenContract: Contract,
  reserveAuction: ReserveAuctionV1,
  fundsRecipient: string,
  curator: string,
  currency = ethers.constants.AddressZero,
  tokenId = 0
) {
  const duration = 60 * 60 * 24;
  const reservePrice = BigNumber.from(10).pow(18).div(2);

  await reserveAuction.createAuction(
    1,
    tokenId,
    tokenContract.address,
    duration,
    reservePrice,
    curator,
    fundsRecipient,
    5,
    currency
  );
}

export async function bid(
  reserveAuction: ReserveAuctionV1,
  auctionId: number,
  amount: BigNumberish,
  currency = ethers.constants.AddressZero
) {
  await reserveAuction.createBid(1, auctionId, amount, {
    value: currency === ethers.constants.AddressZero ? amount : 0,
  });
}

export async function timeTravel(to: number) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [to]);
}

export async function timeTravelToEndOfAuction(
  reserveAuction: ReserveAuctionV1,
  auctionId: number,
  afterEnd = false
) {
  const auction = await reserveAuction.auctions(1, auctionId);
  const base = auction.firstBidTime.add(auction.duration);
  const target = afterEnd ? base : base.sub(1);
  await timeTravel(target.toNumber());
}

export async function endAuction(
  reserveAuction: ReserveAuctionV1,
  auctionId: number
) {
  await reserveAuction.endAuction(1, auctionId);
}

export async function mintERC2981Token(eip2981: TestEip2981Erc721, to: string) {
  await eip2981.mint(to, 0);
}

export async function mintERC721Token(erc721: TestErc721, to: string) {
  await erc721.mint(to, 0);
}
