import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { SimpleModule, ZoraModuleManager } from '../typechain';
import {
  deployProtocolFeeSettings,
  deploySimpleModule,
  deployZoraModuleManager,
  registerModule,
  revert,
} from './utils';

chai.use(asPromised);

describe('ZoraModuleManager', () => {
  let manager: ZoraModuleManager;
  let module: SimpleModule;
  let deployer: Signer;
  let registrar: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    registrar = signers[1];
    otherUser = signers[2];

    const feeSettings = await deployProtocolFeeSettings();
    manager = await deployZoraModuleManager(
      await registrar.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(manager.address);
    module = await deploySimpleModule();
  });

  describe('#isApprovedModule', () => {
    let approvedAddr: string;
    let notApprovedAddr: string;

    beforeEach(async () => {
      const passed = await deploySimpleModule();
      const failed = await deploySimpleModule();

      await registerModule(manager.connect(registrar), passed.address);

      approvedAddr = passed.address;
      notApprovedAddr = failed.address;
    });

    it('should return true if the module has been registered', async () => {
      expect(await manager.moduleRegistered(approvedAddr)).to.eq(true);
    });

    it('should return false if the module has not been registered', async () => {
      expect(await manager.moduleRegistered(notApprovedAddr)).to.eq(false);
    });
  });

  describe('#setApprovalForModule', async () => {
    beforeEach(async () => {
      await registerModule(manager.connect(registrar), module.address);
    });
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

    it('should not allow a user to approve a module that has not been registered', async () => {
      const m = await deploySimpleModule();

      await expect(
        manager.setApprovalForModule(m.address, true)
      ).eventually.rejectedWith(revert`ZMM::must be registered module`);
    });
  });

  xdescribe('#setApprovalForModuleBySig', () => {
    const domain = [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
    ];
    const approval = [
      { name: 'module', type: 'address' },
      { name: 'user', type: 'address' },
      { name: 'approved', type: 'bool' },
    ];
    let domainData: any;

    beforeEach(async () => {
      domainData = {
        name: 'ZORA',
        version: '3',
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: manager.address,
      };
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
          await registerModule(manager.connect(registrar), m);
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

  describe('#registerModule', () => {
    it('should register a module', async () => {
      await registerModule(manager.connect(registrar), module.address);

      const registered = await manager.moduleRegistered(module.address);

      expect(registered).to.eq(true);
    });

    it('should emit a ModuleRegistered event', async () => {
      await registerModule(manager.connect(registrar), module.address);

      const events = await manager.queryFilter(
        manager.filters.ModuleRegistered(null)
      );
      expect(events.length).to.eq(1);
      const logDescription = manager.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ModuleRegistered');
      expect(logDescription.args.module).to.eq(module.address);
    });

    it('should revert if not called by the registrar', async () => {
      await expect(
        registerModule(manager, module.address)
      ).eventually.rejectedWith(revert`ZMM::onlyRegistrar must be registrar`);
    });

    it('should revert if the module has already been registered', async () => {
      await registerModule(manager.connect(registrar), module.address);

      await expect(
        registerModule(manager.connect(registrar), module.address)
      ).eventually.rejectedWith(
        revert`ZMM::registerModule module already registered`
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
      ).eventually.rejectedWith(revert`ZMM::onlyRegistrar must be registrar`);
    });

    it('should revert if attempting to set the registrar to the zero address', async () => {
      await expect(
        manager.connect(registrar).setRegistrar(ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`ZMM::setRegistrar must set registrar to non-zero address`
      );
    });
  });
});
