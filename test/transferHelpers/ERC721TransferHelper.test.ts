import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { TestERC721, TestModuleV1, ZoraModuleManager } from '../../typechain';
import { Signer } from 'ethers';
import {
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployProtocolFeeSettings,
  deployTestERC271,
  deployTestModule,
  deployZoraModuleManager,
  registerModule,
  revert,
} from '../utils';
chai.use(asPromised);

describe('ERC721TransferHelper', () => {
  let nft: TestERC721;
  let moduleManager: ZoraModuleManager;
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

    const feeSettings = await deployProtocolFeeSettings();
    moduleManager = await deployZoraModuleManager(
      await registrar.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(moduleManager.address);

    const erc721Helper = await deployERC721TransferHelper(
      moduleManager.address
    );
    const erc20Helper = await deployERC20TransferHelper(moduleManager.address);

    nft = await deployTestERC271();
    await nft.mint(await otherUser.getAddress(), 1);
    await nft.connect(otherUser).approve(erc721Helper.address, 1);

    module = await deployTestModule(erc20Helper.address, erc721Helper.address);
    badModule = await deployTestModule(
      erc20Helper.address,
      erc721Helper.address
    );

    await registerModule(moduleManager.connect(registrar), module.address);
  });

  it('should allow transfers when the user has approved the module', async () => {
    await moduleManager
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
