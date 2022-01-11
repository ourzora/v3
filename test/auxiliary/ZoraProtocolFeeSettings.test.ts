import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { BigNumber, Signer } from 'ethers';
import { TestERC721, WETH, ZoraProtocolFeeSettings } from '../../typechain';
import {
  deployProtocolFeeSettings,
  deployTestERC721,
  deployWETH,
  revert,
} from '../utils';
chai.use(asPromised);

describe('ZoraProtocolFeeSettings', () => {
  let weth: WETH;
  let owner: Signer;
  let minter: Signer;
  let feeRecipient: Signer;
  let otherUser: Signer;
  let feeSettings: ZoraProtocolFeeSettings;
  let testModuleAddress: string;
  let testERC721: TestERC721;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    const signers = await ethers.getSigners();

    owner = signers[0];
    minter = signers[1];
    feeRecipient = signers[2];
    otherUser = signers[3];
    testModuleAddress = await signers[4].getAddress();
    weth = await deployWETH();
    feeSettings = await deployProtocolFeeSettings();
    testERC721 = await deployTestERC721();
  });

  describe('#init', () => {
    it('should revert if not called by the owner', async () => {
      await expect(
        feeSettings
          .connect(otherUser)
          .init(await otherUser.getAddress(), testERC721.address)
      ).eventually.rejectedWith(revert`init only owner`);
    });

    it('should revert if already initialized', async () => {
      await feeSettings.init(await minter.getAddress(), testERC721.address);

      await expect(
        feeSettings.init(await minter.getAddress(), testERC721.address)
      ).eventually.rejectedWith(revert`init already initialized`);
    });

    it('should set the minter address', async () => {
      await feeSettings.init(await minter.getAddress(), testERC721.address);

      expect(await feeSettings.minter()).to.eq(await minter.getAddress());
    });

    it('should set the metadata address', async () => {
      await feeSettings.init(await minter.getAddress(), testERC721.address);

      expect(await feeSettings.metadata()).to.eq(await testERC721.address);
    });
  });

  describe('#mint', () => {
    beforeEach(async () => {
      feeSettings.init(await minter.getAddress(), testERC721.address);
    });
    it('should revert if not called by the minter', async () => {
      await expect(
        feeSettings.mint(
          await otherUser.getAddress(),
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith(revert`mint onlyMinter`);
    });

    it('should mint a new token to the user', async () => {
      await feeSettings
        .connect(minter)
        .mint(await otherUser.getAddress(), testModuleAddress);

      const tokenID = BigNumber.from(testModuleAddress);
      expect(await feeSettings.ownerOf(tokenID)).to.eq(
        await otherUser.getAddress()
      );
      expect(await feeSettings.tokenIdToModule(tokenID)).to.eq(
        testModuleAddress
      );
      expect(
        (await feeSettings.moduleToTokenId(testModuleAddress)).toString()
      ).to.eq(tokenID.toString());
    });
  });

  describe('#setOwner', () => {
    it('should allow the owner to set a new owner', async () => {
      const block = await ethers.provider.getBlockNumber();
      await feeSettings.setOwner(await otherUser.getAddress());
      const events = await feeSettings.queryFilter(
        feeSettings.filters.OwnerUpdated(null),
        block
      );

      expect(await feeSettings.owner()).to.eq(await otherUser.getAddress());
      expect(events.length).to.eq(1);
      const logDescription = feeSettings.interface.parseLog(events[0]);
      expect(logDescription.args.newOwner).to.eq(await otherUser.getAddress());
    });

    it('should revert if the caller is not owner', async () => {
      await expect(
        feeSettings.connect(otherUser).setOwner(await otherUser.getAddress())
      ).to.eventually.rejectedWith(revert`setOwner onlyOwner`);
    });
  });

  describe('#setMetadata', () => {
    it('should allow the owner to set a new metadata address', async () => {
      const block = await ethers.provider.getBlockNumber();
      await feeSettings.setMetadata(await otherUser.getAddress());
      const events = await feeSettings.queryFilter(
        feeSettings.filters.MetadataUpdated(null),
        block
      );

      expect(await feeSettings.metadata()).to.eq(await otherUser.getAddress());
      expect(events.length).to.eq(1);
      const logDescription = feeSettings.interface.parseLog(events[0]);
      expect(logDescription.args.newMetadata).to.eq(
        await otherUser.getAddress()
      );
    });

    it('should revert if the caller is not owner', async () => {
      await expect(
        feeSettings.connect(otherUser).setMetadata(await otherUser.getAddress())
      ).to.eventually.rejectedWith(revert`setMetadata onlyOwner`);
    });
  });

  describe('#setFeeParams', async () => {
    beforeEach(async () => {
      feeSettings.init(await minter.getAddress(), testERC721.address);
    });

    it('should allow a fee to be set', async () => {
      await feeSettings
        .connect(minter)
        .mint(await owner.getAddress(), testModuleAddress);
      const block = await ethers.provider.getBlockNumber();
      await feeSettings.setFeeParams(
        testModuleAddress,
        await feeRecipient.getAddress(),
        1
      );
      const events = await feeSettings.queryFilter(
        feeSettings.filters.ProtocolFeeUpdated(null, null, null),
        block
      );

      const settings = await feeSettings.moduleFeeSetting(testModuleAddress);
      const recip = settings.feeRecipient;
      const pct = settings.feeBps;
      expect(recip).to.eq(await feeRecipient.getAddress());
      expect(pct).to.eq(1);
      expect(events.length).to.eq(1);
      const logDescription = feeSettings.interface.parseLog(events[0]);
      expect(logDescription.args.feeRecipient).to.eq(
        await feeRecipient.getAddress()
      );
      expect(logDescription.args.feeBps).to.eq(1);
    });

    it('should revert if not called by owner', async () => {
      await feeSettings
        .connect(minter)
        .mint(await owner.getAddress(), testModuleAddress);
      await expect(
        feeSettings
          .connect(otherUser)
          .setFeeParams(testModuleAddress, await feeRecipient.getAddress(), 1)
      ).eventually.rejectedWith(revert`onlyModuleOwner`);
    });

    it('should revert if the fee pct is > 100%', async () => {
      await feeSettings
        .connect(minter)
        .mint(await owner.getAddress(), testModuleAddress);
      await expect(
        feeSettings.setFeeParams(
          testModuleAddress,
          await feeRecipient.getAddress(),
          10001
        )
      ).to.eventually.rejectedWith(revert`setFeeParams must set fee <= 100%`);
    });

    it('should revert if the fee recipient is address(0)', async () => {
      await feeSettings
        .connect(minter)
        .mint(await owner.getAddress(), testModuleAddress);
      await expect(
        feeSettings.setFeeParams(
          testModuleAddress,
          ethers.constants.AddressZero,
          1
        )
      ).to.eventually.rejectedWith(
        revert`setFeeParams fee recipient cannot be 0 address if fee is greater than 0`
      );
    });

    it('should allow the fee parameters to be reset to 0', async () => {
      await feeSettings
        .connect(minter)
        .mint(await owner.getAddress(), testModuleAddress);
      await feeSettings.setFeeParams(
        testModuleAddress,
        ethers.constants.AddressZero,
        0
      );

      const settings = await feeSettings.moduleFeeSetting(testModuleAddress);
      const recip = settings.feeRecipient;
      const pct = settings.feeBps;
      expect(recip).to.eq(ethers.constants.AddressZero);
      expect(pct).to.eq(0);
    });
  });
});
