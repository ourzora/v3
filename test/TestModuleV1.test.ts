import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { TestModuleProxy, TestModuleV1 } from '../typechain';
import {
  connectAs,
  deployTestModule,
  deployTestModuleProxy,
  registerVersion,
} from './utils';
import { Signer } from 'ethers';

chai.use(asPromised);

describe('TestModuleV1', () => {
  let zora: TestModuleProxy;
  let testModule: TestModuleV1;
  let deployer: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    zora = await deployTestModuleProxy();
    const module = await deployTestModule();
    await registerVersion(zora, module.address);
    testModule = await connectAs<TestModuleV1>(zora, 'TestModuleV1');
    const signers = await ethers.getSigners();
    deployer = signers[0];
    otherUser = signers[1];
  });

  describe('#setMagicNumber', () => {
    it('sets the magic number', async () => {
      await testModule.setMagicNumber(1, 1337);

      expect((await testModule.getMagicNumber(1)).toNumber()).to.eq(1337);
    });
  });
});
