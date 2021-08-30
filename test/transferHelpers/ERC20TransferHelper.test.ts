import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  TestModuleV1,
  Weth,
  ZoraModuleApprovalsManager,
  ZoraProposalManager,
} from '../../typechain';
import { Signer } from 'ethers';
import {
  cancelModule,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployTestModule,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
} from '../utils';

chai.use(asPromised);

describe('ERC20TransferHelper', () => {
  let weth: Weth;
  let proposalManager: ZoraProposalManager;
  let approvalsManager: ZoraModuleApprovalsManager;
  let module: TestModuleV1;
  let badModule: TestModuleV1;
  let deployer: Signer;
  let registrar: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    registrar = signers[1];
    otherUser = signers[2];
    weth = await deployWETH();

    await weth.connect(otherUser).deposit({ value: ONE_ETH });

    proposalManager = await deployZoraProposalManager(
      await registrar.getAddress()
    );
    approvalsManager = await deployZoraModuleApprovalsManager(
      proposalManager.address
    );

    const erc721Helper = await deployERC721TransferHelper(
      proposalManager.address,
      approvalsManager.address
    );
    const erc20Helper = await deployERC20TransferHelper(
      proposalManager.address,
      approvalsManager.address
    );

    await weth.connect(otherUser).approve(erc20Helper.address, ONE_ETH);
    module = await deployTestModule(erc20Helper.address, erc721Helper.address);
    badModule = await deployTestModule(
      erc20Helper.address,
      erc721Helper.address
    );
    await proposeModule(proposalManager, module.address);
    await proposeModule(proposalManager, badModule.address);
    await registerModule(proposalManager.connect(registrar), 1);
  });

  it('should allow transfers when the user has approved all modules', async () => {
    await approvalsManager.connect(otherUser).setApprovalForAllModules(true);

    await module.depositERC20(
      weth.address,
      await otherUser.getAddress(),
      ONE_ETH
    );

    expect((await weth.balanceOf(module.address)).toString()).to.eq(
      ONE_ETH.toString()
    );
  });

  it('should allow transfers when the user has approved the module', async () => {
    await approvalsManager
      .connect(otherUser)
      .setApprovalForModule(module.address, true);

    await module.depositERC20(
      weth.address,
      await otherUser.getAddress(),
      ONE_ETH
    );

    expect((await weth.balanceOf(module.address)).toString()).to.eq(
      ONE_ETH.toString()
    );
  });

  it('should not allow transfers when the user has not approved a module', async () => {
    await expect(
      module.depositERC20(weth.address, await otherUser.getAddress(), ONE_ETH)
    ).eventually.rejectedWith(revert`module has not been approved by user`);
  });

  it('should not allow transfers from an unregistered module', async () => {
    await expect(
      badModule.depositERC20(
        weth.address,
        await otherUser.getAddress(),
        ONE_ETH
      )
    ).eventually.rejectedWith(revert`only registered modules`);
  });
});
