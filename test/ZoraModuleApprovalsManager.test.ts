import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  SimpleModule,
  TestERC721,
  ZoraModuleApprovalsManager,
  ZoraProposalManager,
} from '../typechain';
import { Signer } from 'ethers';
import {
  cancelModule,
  deployProtocolFeeSettings,
  deploySimpleModule,
  deployTestERC721,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  proposeModule,
  registerModule,
  revert,
} from './utils';

chai.use(asPromised);

describe('ZoraModuleApprovalsManager', () => {
  let proposalManager: ZoraProposalManager;
  let manager: ZoraModuleApprovalsManager;
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
    proposalManager = await deployZoraProposalManager(
      await registrar.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(proposalManager.address, testERC721.address);
    manager = await deployZoraModuleApprovalsManager(proposalManager.address);
    module = await deploySimpleModule();
    await proposeModule(proposalManager, module.address);
    await registerModule(proposalManager.connect(registrar), module.address);
  });

  describe('#setApprovalForModule', async () => {
    it('should set approval for a module', async () => {
      await manager
        .connect(otherUser)
        .setApprovalForModule(module.address, true);

      expect(
        await manager.userApprovals(
          await otherUser.getAddress(),
          module.address
        )
      ).to.eq(true);
    });

    it('should emit a ModuleApprovalSet event', async () => {
      await manager
        .connect(otherUser)
        .setApprovalForModule(module.address, true);

      const events = await manager.queryFilter(
        manager.filters.ModuleApprovalSet(null, null, null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ModuleApprovalSet');
      expect(logDescription.args.user).to.eq(await otherUser.getAddress());
      expect(logDescription.args.module).to.eq(module.address);
      expect(logDescription.args.approved).to.eq(true);
    });

    it('should not allow a user to approve a module that has not been proposed', async () => {
      const m = await deploySimpleModule();

      await expect(
        manager.setApprovalForModule(m.address, true)
      ).eventually.rejectedWith(revert`ZMAM::module must be approved`);
    });

    it('should not allow a user to approve a module that has a pending proposal', async () => {
      const m = await deploySimpleModule();
      await proposeModule(proposalManager.connect(registrar), m.address);

      await expect(
        manager.setApprovalForModule(m.address, true)
      ).eventually.rejectedWith(revert`ZMAM::module must be approved`);
    });

    it('should not allow a user to approve a module that has failed', async () => {
      const m = await deploySimpleModule();
      await proposeModule(proposalManager.connect(registrar), m.address);
      await cancelModule(proposalManager.connect(registrar), m.address);

      await expect(
        manager.setApprovalForModule(m.address, true)
      ).eventually.rejectedWith(revert`ZMAM::module must be approved`);
    });
  });

  describe('#setBatchApprovalForModules', () => {
    it('should approve an array of modules', async () => {
      const modules = [
        await deploySimpleModule(),
        await deploySimpleModule(),
        await deploySimpleModule(),
        await deploySimpleModule(),
      ].map((m) => m.address);
      await Promise.all(
        modules.map(async (m) => {
          await proposeModule(proposalManager.connect(registrar), m);
          await registerModule(proposalManager.connect(registrar), m);
        })
      );
      await manager
        .connect(otherUser)
        .setBatchApprovalForModules(modules, true);
      await Promise.all(
        modules.map((m) => {
          return (async () =>
            expect(
              await manager.userApprovals(await otherUser.getAddress(), m)
            ).to.eq(true))();
        })
      );
    });
  });
});
