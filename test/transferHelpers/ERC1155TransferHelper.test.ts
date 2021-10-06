import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  TestErc1155,
  TestModuleV1,
  TestModuleV2,
  Weth,
  ZoraModuleApprovalsManager,
  ZoraProposalManager,
} from '../../typechain';
import { Signer } from 'ethers';
import {
  cancelModule,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployERC1155TransferHelper,
  deployTestERC1155,
  deployTestModule,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
  deployTestModuleV2,
} from '../utils';

chai.use(asPromised);

describe('ERC1155TransferHelper', () => {
  let tokens: TestErc1155;
  let proposalManager: ZoraProposalManager;
  let approvalsManager: ZoraModuleApprovalsManager;
  let moduleV1: TestModuleV1;
  let moduleV2: TestModuleV2;
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
    approvalsManager = await deployZoraModuleApprovalsManager(
      proposalManager.address
    );

    const erc1155Helper = await deployERC1155TransferHelper(
      approvalsManager.address
    );
    const erc721Helper = await deployERC721TransferHelper(
      approvalsManager.address
    );
    const erc20Helper = await deployERC20TransferHelper(
      approvalsManager.address
    );

    tokens = await deployTestERC1155();
    await tokens.mintBatch(
      await otherUser.getAddress(),
      [0, 1],
      [ethers.utils.parseUnits('50'), ethers.utils.parseUnits('50')]
    );
    await tokens
      .connect(otherUser)
      .setApprovalForAll(erc1155Helper.address, true);

    moduleV1 = await deployTestModule(
      erc20Helper.address,
      erc721Helper.address
    );
    moduleV2 = await deployTestModuleV2(erc1155Helper.address);

    await proposeModule(proposalManager, moduleV2.address);
    await proposeModule(proposalManager, moduleV1.address);

    await registerModule(proposalManager.connect(registrar), moduleV2.address);
    await registerModule(proposalManager.connect(registrar), moduleV1.address);
  });

  it('should allow single token transfers when the user has approved the module', async () => {
    await approvalsManager
      .connect(otherUser)
      .setApprovalForModule(moduleV2.address, true);

    await moduleV2.depositERC1155(
      tokens.address,
      await otherUser.getAddress(),
      0,
      ethers.utils.parseUnits('25')
    );

    expect((await tokens.balanceOf(moduleV2.address, 0)).toString()).to.eq(
      ethers.utils.parseUnits('25').toString()
    );
  });

  it('should allow multi token transfers when the user has approved the module', async () => {
    await approvalsManager
      .connect(otherUser)
      .setApprovalForModule(moduleV2.address, true);

    await moduleV2.batchDepositERC1155(
      tokens.address,
      await otherUser.getAddress(),
      [0, 1],
      [ethers.utils.parseUnits('25'), ethers.utils.parseUnits('25')]
    );

    expect((await tokens.balanceOf(moduleV2.address, 0)).toString()).to.eq(
      ethers.utils.parseUnits('25').toString()
    );

    expect((await tokens.balanceOf(moduleV2.address, 1)).toString()).to.eq(
      ethers.utils.parseUnits('25').toString()
    );
  });

  it('should not allow single token transfers when the user has not approved a module', async () => {
    await expect(
      moduleV2.depositERC1155(
        tokens.address,
        await otherUser.getAddress(),
        0,
        ethers.utils.parseUnits('25')
      )
    ).eventually.rejectedWith(revert`module has not been approved by user`);
  });

  it('should not allow multi token transfers when the user has not approved a module', async () => {
    await expect(
      moduleV2.batchDepositERC1155(
        tokens.address,
        await otherUser.getAddress(),
        [0, 1],
        [ethers.utils.parseUnits('25'), ethers.utils.parseUnits('25')]
      )
    ).eventually.rejectedWith(revert`module has not been approved by user`);
  });
});
