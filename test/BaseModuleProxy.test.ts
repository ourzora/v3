import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  deployBaseModuleProxy,
  deployTestModule,
  registerVersion,
} from './utils';
import { Signer } from 'ethers';
import { BaseModuleProxy, TestModuleProxy } from '../typechain';

chai.use(asPromised);

describe('BaseModuleProxy', () => {
  let proxy: BaseModuleProxy;
  let deployer: Signer;
  let proposer: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    proxy = await deployBaseModuleProxy();
    const signers = await ethers.getSigners();
    deployer = signers[0];
    proposer = signers[1];
    otherUser = signers[2];
  });

  describe('#registerVersion', () => {
    it('registers a valid module', async () => {
      const module = await deployTestModule();
      await registerVersion(proxy.connect(proposer), module.address);

      expect(await proxy.versionToImplementationAddress(1)).to.eq(
        module.address
      );
      expect(
        (await proxy.implementationAddressToVersion(module.address)).toNumber()
      ).to.eq(1);
    });
  });
});
