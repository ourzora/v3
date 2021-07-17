import { ethers } from 'hardhat';
import { BaseModuleProxy, TestModuleProxy, TestModuleV1 } from '../typechain';
import { Contract } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';

export const revert = (messages: TemplateStringsArray, ...rest) =>
  `VM Exception while processing transaction: reverted with reason string '${messages[0]}'`;

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

export const connectAs = async <T extends unknown>(
  proxy: Contract,
  moduleName: string
) => {
  const Factory = await ethers.getContractFactory(moduleName);
  return Factory.attach(proxy.address) as T;
};

export const registerVersion = async (
  zora: BaseModuleProxy,
  moduleAddress: string,
  callData: BytesLike = []
) => {
  await zora.registerVersion(moduleAddress, callData);
};
