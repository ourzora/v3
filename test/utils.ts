import { ethers } from 'hardhat';
import {
  BadErc721,
  ReserveAuctionV1,
  TestEip2981Erc721,
  TestErc721,
  TestModuleV1,
  Weth,
  ZoraProposalManager,
  ZoraModuleApprovalsManager,
  Erc20TransferHelper,
  Erc721TransferHelper,
  SimpleModule,
  ListingsV1,
} from '../typechain';
import { BigNumber, BigNumberish, Contract } from 'ethers';
import {
  Erc721,
  MarketFactory,
  Media,
  MediaFactory,
} from '@zoralabs/core/dist/typechain';

export const revert = (messages: TemplateStringsArray, ...rest) =>
  `VM Exception while processing transaction: reverted with reason string '${messages[0]}'`;

export const ONE_DAY = 24 * 60 * 60;
export const ONE_ETH = ethers.utils.parseEther('1');
export const TWO_ETH = ethers.utils.parseEther('2');
export const TENTH_ETH = ethers.utils.parseEther('0.1');
export const THOUSANDTH_ETH = ethers.utils.parseEther('0.001');

// Helper function to parse numbers and do approximate number calculations
export const toRoundedNumber = (bn: BigNumber) =>
  bn.div(THOUSANDTH_ETH).toNumber();

export const deployZoraProposalManager = async (registrar: string) => {
  const ZoraProposalManagerFactory = await ethers.getContractFactory(
    'ZoraProposalManager'
  );
  const proposalManager = await ZoraProposalManagerFactory.deploy(registrar);
  await proposalManager.deployed();
  return proposalManager as ZoraProposalManager;
};

export const proposeModule = async (
  manager: ZoraProposalManager,
  moduleAddr: string
) => {
  return manager.proposeModule(moduleAddr);
};

export const registerModule = async (
  manager: ZoraProposalManager,
  moduleAddress: string
) => {
  return manager.registerModule(moduleAddress);
};

export const cancelModule = async (
  manager: ZoraProposalManager,
  moduleAddress: string
) => {
  return manager.cancelProposal(moduleAddress);
};

export const deployZoraModuleApprovalsManager = async (
  proposalManagerAddr: string
) => {
  const ZoraModuleApprovalsManager = await ethers.getContractFactory(
    'ZoraModuleApprovalsManager'
  );
  const approvalsManager = await ZoraModuleApprovalsManager.deploy(
    proposalManagerAddr
  );
  await approvalsManager.deployed();

  return approvalsManager as ZoraModuleApprovalsManager;
};

export const deployERC20TransferHelper = async (
  proposalManager: string,
  approvalsManager: string
) => {
  const ERC20TransferHelperFactory = await ethers.getContractFactory(
    'ERC20TransferHelper'
  );
  const transferHelper = await ERC20TransferHelperFactory.deploy(
    proposalManager,
    approvalsManager
  );
  await transferHelper.deployed();

  return transferHelper as Erc20TransferHelper;
};

export const deployERC721TransferHelper = async (
  proposalManager: string,
  approvalsManager: string
) => {
  const ERC721TransferHelperFactory = await ethers.getContractFactory(
    'ERC721TransferHelper'
  );
  const transferHelper = await ERC721TransferHelperFactory.deploy(
    proposalManager,
    approvalsManager
  );
  await transferHelper.deployed();

  return transferHelper as Erc721TransferHelper;
};

export const deployTestModule = async (
  erc20Helper: string,
  erc721Helper: string
) => {
  const TestModuleFactory = await ethers.getContractFactory('TestModuleV1');
  const testModule = await TestModuleFactory.deploy(erc20Helper, erc721Helper);
  await testModule.deployed();
  return testModule as TestModuleV1;
};

export const deploySimpleModule = async () => {
  const SimpleModuleFactory = await ethers.getContractFactory('SimpleModule');
  const simpleModule = await SimpleModuleFactory.deploy();
  await simpleModule.deployed();

  return simpleModule as SimpleModule;
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

export const deployReserveAuctionV1 = async (
  proposalManager: string,
  approvalsManager: string,
  zoraV1Media: string,
  weth: string
) => {
  const ReserveAuctionV1Factory = await ethers.getContractFactory(
    'ReserveAuctionV1'
  );
  const reserveAuction = await ReserveAuctionV1Factory.deploy(
    proposalManager,
    approvalsManager,
    zoraV1Media,
    weth
  );
  await reserveAuction.deployed();
  return reserveAuction as ReserveAuctionV1;
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
  await reserveAuction.createBid(auctionId, amount, {
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
  const auction = await reserveAuction.auctions(auctionId);
  const base = auction.firstBidTime.add(auction.duration);
  const target = afterEnd ? base : base.sub(1);
  await timeTravel(target.toNumber());
}

export async function endAuction(
  reserveAuction: ReserveAuctionV1,
  auctionId: number
) {
  await reserveAuction.endAuction(auctionId);
}

export async function mintERC2981Token(eip2981: TestEip2981Erc721, to: string) {
  await eip2981.mint(to, 0);
}

export async function mintERC721Token(erc721: TestErc721, to: string) {
  await erc721.mint(to, 0);
}

export async function deployListingsV1(
  erc20Helper: string,
  erc721Helper: string,
  zoraV1Media: string,
  weth: string
) {
  const ListingsV1Factory = await ethers.getContractFactory('ListingsV1');
  const listings = await ListingsV1Factory.deploy(
    erc20Helper,
    erc721Helper,
    zoraV1Media,
    weth
  );
  await listings.deployed();
  return listings as ListingsV1;
}
