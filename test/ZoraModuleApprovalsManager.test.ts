import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  SimpleModule,
  ZoraModuleApprovalsManager,
  ZoraProposalManager,
} from '../typechain';
import { Signer } from 'ethers';
import {
  deploySimpleModule,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
} from './utils';

chai.use(asPromised);

describe('ZoraModuleApprovalsManager', () => {
  let proposalManager: ZoraProposalManager;
  let manager: ZoraModuleApprovalsManager;
  let module: SimpleModule;
  let deployer: Signer;
  let registrar: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    registrar = signers[1];
    otherUser = signers[2];

    proposalManager = await deployZoraProposalManager(
      await registrar.getAddress()
    );
    manager = await deployZoraModuleApprovalsManager(proposalManager.address);
    module = await deploySimpleModule();
  });

  describe('#setApprovalForAllModules', async () => {
    it("should set a user's approval for all modules", async () => {
      await manager.connect(otherUser).setApprovalForAllModules(true);

      expect(await manager.approvedForAll(await otherUser.getAddress())).to.eq(
        true
      );
    });
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
  });

  describe('#setBatchApprovalForModules', () => {
    it('should approve an array of modules', async () => {
      const modules = [
        await deploySimpleModule(),
        await deploySimpleModule(),
        await deploySimpleModule(),
        await deploySimpleModule(),
      ].map((m) => m.address);
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
