import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { TestModuleV1, WETH, ZoraModuleManager } from '../../typechain';
import { Signer } from 'ethers';
import {
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployProtocolFeeSettings,
  deployTestModule,
  deployWETH,
  deployZoraModuleManager,
  ONE_ETH,
  registerModule,
  revert,
} from '../utils';
chai.use(asPromised);

describe('ERC20TransferHelper', () => {
  let weth: WETH;
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
    weth = await deployWETH();

    await weth.connect(otherUser).deposit({ value: ONE_ETH });

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

    await weth.connect(otherUser).approve(erc20Helper.address, ONE_ETH);
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
