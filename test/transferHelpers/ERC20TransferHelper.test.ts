import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  TestERC721,
  TestModuleV1,
  WETH,
  ZoraModuleApprovalsManager,
  ZoraProposalManager,
} from '../../typechain';
import { Signer } from 'ethers';
import {
  cancelModule,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployProtocolFeeSettings,
  deployTestERC721,
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
  let weth: WETH;
  let proposalManager: ZoraProposalManager;
  let approvalsManager: ZoraModuleApprovalsManager;
  let module: TestModuleV1;
  let badModule: TestModuleV1;
  let deployer: Signer;
  let registrar: Signer;
  let otherUser: Signer;
  let testERC721: TestERC721;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    registrar = signers[1];
    otherUser = signers[2];
    weth = await deployWETH();
    testERC721 = await deployTestERC721();

    await weth.connect(otherUser).deposit({ value: ONE_ETH });

    const feeSettings = await deployProtocolFeeSettings();
    proposalManager = await deployZoraProposalManager(
      await registrar.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(proposalManager.address, testERC721.address);
    approvalsManager = await deployZoraModuleApprovalsManager(
      proposalManager.address
    );

    const erc721Helper = await deployERC721TransferHelper(
      approvalsManager.address
    );
    const erc20Helper = await deployERC20TransferHelper(
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
    await registerModule(proposalManager.connect(registrar), module.address);
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
});
