import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  BaseModuleProxy,
  TestModuleV1,
  TestModuleV1Factory,
} from '../../typechain';
import {
  connectAs,
  deployTestModule,
  deployBaseModuleProxy,
  proposeVersion,
  registerVersion,
} from '../utils';
import { Signer } from 'ethers';

chai.use(asPromised);

describe('TestModuleV1', () => {
  let proxy: BaseModuleProxy;
  let testModule: TestModuleV1;
  let deployer: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    otherUser = signers[1];
    proxy = await deployBaseModuleProxy(await deployer.getAddress());
    const module = await deployTestModule();
    await proposeVersion(proxy, module.address);
    await registerVersion(proxy, 1);
    testModule = await connectAs<TestModuleV1>(proxy, 'TestModuleV1');
  });

  describe('#setMagicNumber', () => {
    it('sets the magic number', async () => {
      await testModule.setMagicNumber(1, 1337);

      expect((await testModule.getMagicNumber(1)).toNumber()).to.eq(1337);
    });

    it('emits an MagicNumberUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await testModule.setMagicNumber(1, 1337);

      const events = await testModule.queryFilter(
        new TestModuleV1Factory()
          .attach(testModule.address)
          .filters.MagicNumberUpdated(null, null),
        block
      );
      const description = await testModule.interface.parseLog(events[0]);

      expect(description.args.version.toNumber()).to.eq(1);
      expect(
        description.args.data.map((m) => m.toNumber())
      ).to.have.ordered.members([1337]);
    });
  });
});
