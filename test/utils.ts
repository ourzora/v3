import { ethers } from 'hardhat';
import {
  BaseModuleProxy,
  ReserveAuctionProxy,
  ReserveAuctionV1,
  TestModuleProxy,
  TestModuleV1,
} from '../typechain';
import { Contract } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';
import { MarketFactory, MediaFactory } from '@zoralabs/core/dist/typechain';

export const revert = (messages: TemplateStringsArray, ...rest) =>
  `VM Exception while processing transaction: reverted with reason string '${messages[0]}'`;

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

export const deployReserveAuctionProxy = async () => {
  const ReserveAuctionProxyFactory = await ethers.getContractFactory(
    'ReserveAuctionProxy'
  );
  const reserveAuctionProxy = await ReserveAuctionProxyFactory.deploy();
  await reserveAuctionProxy.deployed();
  return reserveAuctionProxy as ReserveAuctionProxy;
};

export const deployReserveAuctionV1 = async (proxyAddr: string) => {
  const ReserveAuctionV1Factory = await ethers.getContractFactory(
    'ReserveAuctionV1'
  );
  const reserveAuction = await ReserveAuctionV1Factory.deploy(proxyAddr);
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
