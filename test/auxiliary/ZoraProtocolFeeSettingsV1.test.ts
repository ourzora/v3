import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { WETH, ZoraProtocolFeeSettingsV1 } from '../../typechain';
import { deployProtocolFeeSettings, deployWETH, revert } from '../utils';
chai.use(asPromised);

describe('ZoraProtocolFeeSettingsV1', () => {
  let weth: WETH;
  let owner: Signer;
  let feeRecipient: Signer;
  let otherUser: Signer;
  let feeSettings: ZoraProtocolFeeSettingsV1;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    const signers = await ethers.getSigners();

    owner = signers[0];
    feeRecipient = signers[1];
    otherUser = signers[2];
    weth = await deployWETH();
    feeSettings = await deployProtocolFeeSettings(await owner.getAddress());
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
      expect(events.length).to.eq(2);
      const logDescription = feeSettings.interface.parseLog(events[1]);
      expect(logDescription.args.newOwner).to.eq(await otherUser.getAddress());
    });

    it('should revert if the caller is not owner', async () => {
      await expect(
        feeSettings.connect(otherUser).setOwner(await otherUser.getAddress())
      ).to.eventually.rejectedWith(revert`onlyOwner`);
    });
  });

  describe('#setFeeParams', async () => {
    it('should allow a fee to be set', async () => {
      const block = await ethers.provider.getBlockNumber();
      await feeSettings.setFeeParams(await feeRecipient.getAddress(), 1);
      const events = await feeSettings.queryFilter(
        feeSettings.filters.ProtocolFeeUpdated(null, null)
      );

      const recip = await feeSettings.feeRecipient();
      const pct = await feeSettings.feePct();
      expect(recip).to.eq(await feeRecipient.getAddress());
      expect(pct).to.eq(1);
      expect(events.length).to.eq(1);
      const logDescription = feeSettings.interface.parseLog(events[0]);
      expect(logDescription.args.feeRecipient).to.eq(
        await feeRecipient.getAddress()
      );
      expect(logDescription.args.feePct).to.eq(1);
    });

    it('should revert if not called by owner', async () => {
      await expect(
        feeSettings
          .connect(otherUser)
          .setFeeParams(await feeRecipient.getAddress(), 1)
      ).eventually.rejectedWith(revert`onlyOwner`);
    });

    it('should revert if the fee pct is > 100%', async () => {
      await expect(
        feeSettings.setFeeParams(await feeRecipient.getAddress(), 101)
      ).to.eventually.rejectedWith(revert`setFeeParams must set fee <= 100%`);
    });

    it('should revert if the fee recipient is address(0)', async () => {
      await expect(
        feeSettings.setFeeParams(ethers.constants.AddressZero, 1)
      ).to.eventually.rejectedWith(
        revert`setFeeParams fee recipient cannot be 0 address if fee is greater than 0`
      );
    });

    it('should allow the fee parameters to be reset to 0', async () => {
      await feeSettings.setFeeParams(ethers.constants.AddressZero, 0);

      const recip = await feeSettings.feeRecipient();
      const pct = await feeSettings.feePct();
      expect(recip).to.eq(ethers.constants.AddressZero);
      expect(pct).to.eq(0);
    });
  });
});
