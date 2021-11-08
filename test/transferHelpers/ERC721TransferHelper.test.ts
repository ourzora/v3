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
  deployTestERC271,
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

describe('ERC721TransferHelper', () => {
  let nft: TestERC721;
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

    proposalManager = await deployZoraProposalManager(
      await registrar.getAddress()
    );
    approvalsManager = await deployZoraModuleApprovalsManager(
      proposalManager.address
    );

    const erc721Helper = await deployERC721TransferHelper(
      approvalsManager.address
    );
    const erc20Helper = await deployERC20TransferHelper(
      approvalsManager.address
    );

    nft = await deployTestERC271();
    await nft.mint(await otherUser.getAddress(), 1);
    await nft.connect(otherUser).approve(erc721Helper.address, 1);

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

    await module.depositERC721(nft.address, await otherUser.getAddress(), 1);

    expect(await nft.ownerOf(1)).to.eq(module.address);
  });

  it('should not allow transfers when the user has not approved a module', async () => {
    await expect(
      module.depositERC721(nft.address, await otherUser.getAddress(), 1)
    ).eventually.rejectedWith(revert`module has not been approved by user`);
  });
});
