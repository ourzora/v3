import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { SimpleModule, TestERC721, ZoraProposalManager } from '../typechain';
import { Signer } from 'ethers';
import {
  cancelModule,
  deployProtocolFeeSettings,
  deploySimpleModule,
  deployTestERC721,
  deployZoraProposalManager,
  proposeModule,
  registerModule,
  revert,
} from './utils';

chai.use(asPromised);

describe('ZoraProposalManager', () => {
  let manager: ZoraProposalManager;
  let module: SimpleModule;
  let deployer: Signer;
  let registrar: Signer;
  let otherUser: Signer;
  let testERC721: TestERC721;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    registrar = signers[1];
    otherUser = signers[2];

    testERC721 = await deployTestERC721();

    const feeSettings = await deployProtocolFeeSettings();
    manager = await deployZoraProposalManager(
      await registrar.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(manager.address, testERC721.address);
    module = await deploySimpleModule();
  });

  describe('#isPassedProposal', () => {
    let pendingAddr: string;
    let passedAddr: string;
    let failedAddr: string;

    beforeEach(async () => {
      const passed = await deploySimpleModule();
      const failed = await deploySimpleModule();

      await proposeModule(manager, module.address);

      await proposeModule(manager, passed.address);
      await registerModule(manager.connect(registrar), passed.address);

      await proposeModule(manager, failed.address);
      await cancelModule(manager.connect(registrar), failed.address);

      pendingAddr = module.address;
      passedAddr = passed.address;
      failedAddr = failed.address;
    });

    it('should return true if the proposal has passed', async () => {
      expect(await manager.isPassedProposal(passedAddr)).to.eq(true);
    });

    it('should return false if the proposal is pending', async () => {
      expect(await manager.isPassedProposal(pendingAddr)).to.eq(false);
    });

    it('should return false if the proposal failed', async () => {
      expect(await manager.isPassedProposal(failedAddr)).to.eq(false);
    });
  });

  describe('#proposeModule', () => {
    it('should create a proposal', async () => {
      await proposeModule(manager, module.address);

      const proposal = await manager.proposedModuleToProposal(module.address);

      expect(proposal.status).to.eq(1);
      expect(proposal.proposer).to.eq(await deployer.getAddress());
    });

    it('should emit a ModuleProposed event', async () => {
      await proposeModule(manager, module.address);

      const events = await manager.queryFilter(
        manager.filters.ModuleProposed(null, null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ModuleProposed');
      expect(logDescription.args.contractAddress).to.eq(module.address);
      expect(logDescription.args.proposer).to.eq(await deployer.getAddress());
    });

    it('should revert if the module has already been proposed', async () => {
      await proposeModule(manager, module.address);

      await expect(
        proposeModule(manager, module.address)
      ).eventually.rejectedWith(
        revert`ZPM::proposeModule proposal already exists`
      );
    });

    it('should revert if the implementation address is 0x0', async () => {
      await expect(
        proposeModule(manager, ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`ZPM::proposeModule proposed contract cannot be zero address`
      );
    });
  });

  describe('#registerModule', () => {
    beforeEach(async () => {
      await proposeModule(manager, module.address);
    });

    it('should register a module', async () => {
      await registerModule(manager.connect(registrar), module.address);

      const proposal = await manager.proposedModuleToProposal(module.address);

      expect(proposal.status).to.eq(2);
    });

    it('should emit a ModuleRegistered event', async () => {
      await registerModule(manager.connect(registrar), module.address);

      const events = await manager.queryFilter(
        manager.filters.ModuleRegistered(null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ModuleRegistered');
      expect(logDescription.args.contractAddress).to.eq(module.address);
    });

    it('should revert if not called by the registrar', async () => {
      await expect(
        registerModule(manager, module.address)
      ).eventually.rejectedWith(revert`ZPM::onlyRegistrar must be registrar`);
    });

    it('should revert if the proposal does not exist', async () => {
      await expect(
        registerModule(manager.connect(registrar), ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`ZPM::registerModule can only register pending proposals`
      );
    });

    it('should revert if the proposal has already passed', async () => {
      await registerModule(manager.connect(registrar), module.address);

      await expect(
        registerModule(manager.connect(registrar), module.address)
      ).eventually.rejectedWith(
        revert`ZPM::registerModule can only register pending proposals`
      );
    });

    it('should revert if the proposal has already failed', async () => {
      await cancelModule(manager.connect(registrar), module.address);

      await expect(
        registerModule(manager.connect(registrar), module.address)
      ).eventually.rejectedWith(
        revert`ZPM::registerModule can only register pending proposals`
      );
    });
  });

  describe('#cancelProposal', async () => {
    beforeEach(async () => {
      await proposeModule(manager, module.address);
    });

    it('should cancel a proposal', async () => {
      await cancelModule(manager.connect(registrar), module.address);

      const proposal = await manager.proposedModuleToProposal(module.address);

      await expect(proposal.status).to.eq(3);
    });

    it('should emit a ModuleCanceled event', async () => {
      await cancelModule(manager.connect(registrar), module.address);

      const events = await manager.queryFilter(
        manager.filters.ModuleCanceled(null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ModuleCanceled');
      expect(logDescription.args.contractAddress).to.eq(module.address);
    });

    it('should revert if not called by the registrar', async () => {
      await expect(
        cancelModule(manager.connect(otherUser), module.address)
      ).eventually.rejectedWith(revert`ZPM::onlyRegistrar must be registrar`);
    });

    it('should revert if the proposal does not exist', async () => {
      await expect(
        cancelModule(manager.connect(registrar), ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`ZPM::cancelProposal can only cancel pending proposals`
      );
    });
    it('should revert if the proposal has already been approved', async () => {
      await registerModule(manager.connect(registrar), module.address);

      await expect(
        cancelModule(manager.connect(registrar), module.address)
      ).eventually.rejectedWith(
        'ZPM::cancelProposal can only cancel pending proposals'
      );
    });

    it('should revert if the proposal has already been cancelled', async () => {
      await cancelModule(manager.connect(registrar), module.address);

      await expect(
        cancelModule(manager.connect(registrar), module.address)
      ).eventually.rejectedWith(
        'ZPM::cancelProposal can only cancel pending proposals'
      );
    });
  });

  describe('#setRegistrar', async () => {
    it('should set the registrar', async () => {
      await manager
        .connect(registrar)
        .setRegistrar(await otherUser.getAddress());

      expect(await manager.registrar()).to.eq(await otherUser.getAddress());
    });

    it('should emit a RegistrarChanged event', async () => {
      await manager
        .connect(registrar)
        .setRegistrar(await otherUser.getAddress());

      const events = await manager.queryFilter(
        manager.filters.RegistrarChanged(null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('RegistrarChanged');
      expect(logDescription.args.newRegistrar).to.eq(
        await otherUser.getAddress()
      );
    });

    it('should revert if not called by the registrar', async () => {
      await expect(
        manager.setRegistrar(await otherUser.getAddress())
      ).eventually.rejectedWith(revert`ZPM::onlyRegistrar must be registrar`);
    });

    it('should revert if attempting to set the registrar to the zero address', async () => {
      await expect(
        manager.connect(registrar).setRegistrar(ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`ZPM::setRegistrar must set registrar to non-zero address`
      );
    });
  });
});
