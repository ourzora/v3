import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  cancelProposal,
  deployBaseModuleProxy,
  deployTestModule,
  proposeVersion,
  registerVersion,
  revert,
} from './utils';
import { Signer } from 'ethers';
import { BaseModuleProxy, TestModuleV1 } from '../typechain';

chai.use(asPromised);

describe('BaseModuleProxy', () => {
  let proxy: BaseModuleProxy;
  let deployer: Signer;
  let proposer: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    proposer = signers[1];
    otherUser = signers[2];
    proxy = await deployBaseModuleProxy(await deployer.getAddress());
  });

  describe('#proposeVersion', () => {
    it('should revert if a proposal has already been created for an implementation', async () => {
      const module = await deployTestModule();
      await proposeVersion(proxy.connect(proposer), module.address);

      await expect(
        proposeVersion(proxy.connect(proposer), module.address)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::proposeVersion implementation address already in use`
      );
    });

    it('should revert if the proposal is for a zero address', async () => {
      const module = await deployTestModule();
      await expect(
        proposeVersion(proxy.connect(proposer), ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::proposeVersion cannot propose zero address implementation`
      );
    });

    it('should add a new proposal', async () => {
      const module = await deployTestModule();
      await proposeVersion(proxy.connect(proposer), module.address);

      const proposal = await proxy.proposal(1);

      expect(proposal.implementationAddress).to.eq(module.address);
      expect(proposal.status).to.eq(0);
      expect(proposal.proposer).to.eq(await proposer.getAddress());
    });
  });

  describe('#registerVersion', () => {
    let module: TestModuleV1;

    beforeEach(async () => {
      module = await deployTestModule();
      await proposeVersion(proxy, module.address);
    });

    it('should not be callable by non-registrar', async () => {
      await expect(
        registerVersion(proxy.connect(proposer), 1)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::registerVersion only callable by registrar`
      );
    });

    it('should revert if the proposal does not exist', async () => {
      await expect(registerVersion(proxy, 11111)).eventually.rejectedWith(
        revert`LibVersionRegistry::registerVersion nonexistant proposal`
      );
    });

    it('should revert if the proposal memory slot is already in use', async () => {
      const m1 = await deployTestModule();
      const m2 = await deployTestModule();
      await proposeVersion(proxy.connect(proposer), m1.address);
      await proposeVersion(proxy.connect(proposer), m2.address);
      await registerVersion(proxy.connect(deployer), 2);
      await expect(
        registerVersion(proxy.connect(deployer), 3)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::registerVersion storage slot already allocated`
      );
      const failedProposal = await proxy.proposal(3);
    });

    it('cannot register a canceled proposal', async () => {
      await cancelProposal(proxy.connect(deployer), 1);

      await expect(
        registerVersion(proxy.connect(deployer), 1)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::registerVersion proposal must be pending`
      );
    });

    it('cannot register a passed proposal', async () => {
      await registerVersion(proxy.connect(deployer), 1);

      await expect(
        registerVersion(proxy.connect(deployer), 1)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::registerVersion proposal must be pending`
      );
    });

    it('registers a valid module', async () => {
      await registerVersion(proxy, 1);

      expect(await proxy.versionToImplementationAddress(1)).to.eq(
        module.address
      );
      expect(
        (await proxy.implementationAddressToVersion(module.address)).toNumber()
      ).to.eq(1);
    });
  });

  describe('#cancelProposal', () => {
    let module: TestModuleV1;

    beforeEach(async () => {
      module = await deployTestModule();
      await proposeVersion(proxy.connect(proposer), module.address);
    });

    it('should only be callable by the registrar', async () => {
      await expect(
        cancelProposal(proxy.connect(otherUser), 1)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::cancelProposal only callable by registrar`
      );
    });

    it('should revert if the proposal does not exist', async () => {
      await expect(
        cancelProposal(proxy.connect(deployer), 111111)
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::cancelProposal proposal does not exist`
      );
    });

    it('should cancel the proposal', async () => {
      await cancelProposal(proxy.connect(deployer), 1);

      const proposal = await proxy.proposal(1);

      expect(proposal.proposer).to.eq(await proposer.getAddress());
      expect(proposal.implementationAddress).to.eq(module.address);
      expect(proposal.status).to.eq(2);
    });
  });

  describe('#setRegistrar', () => {
    it('should revert if not called by the registrar', async () => {
      await expect(
        proxy.connect(otherUser).setRegistrar(await otherUser.getAddress())
      ).eventually.rejectedWith(
        revert`LibVersionRegistry::setRegistrar only callable by registrar`
      );
    });

    it('should set the registrar', async () => {
      await proxy.setRegistrar(await otherUser.getAddress());

      expect(await proxy.registrar()).to.eq(await otherUser.getAddress());
    });
  });
});
