import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import {
  BadErc721,
  TestErc721,
  CollectionRoyaltyRegistryV1,
} from '../../../typechain';
import {
  deployBadERC721,
  deployRoyaltyRegistry,
  deployTestERC271,
  revert,
} from '../../utils';

chai.use(asPromised);

describe('CollectionRoyaltyRegistryV1', async () => {
  let deployer: Signer;
  let otherUser: Signer;
  let badNFT: BadErc721;
  let testNFT: TestErc721;
  let royaltyRegistry: CollectionRoyaltyRegistryV1;

  beforeEach(async () => {
    [deployer, otherUser] = await ethers.getSigners();
    badNFT = await deployBadERC721();
    testNFT = await deployTestERC271();
    royaltyRegistry = await deployRoyaltyRegistry();
  });

  describe('#setRoyaltyRegistry', () => {
    it('should set the royalties for a collection', async () => {
      await royaltyRegistry.setRoyalty(
        testNFT.address,
        await deployer.getAddress(),
        10
      );

      const royalties = await royaltyRegistry.collectionRoyalty(
        testNFT.address
      );

      expect(royalties.recipient).to.eq(await deployer.getAddress());
      expect(royalties.royaltyPercentage).to.eq(10);
    });

    it('should emit a CollectionRoyaltyUpdated event', async () => {
      await royaltyRegistry.setRoyalty(
        testNFT.address,
        await deployer.getAddress(),
        10
      );

      const events = await royaltyRegistry.queryFilter(
        royaltyRegistry.filters.CollectionRoyaltyUpdated(null, null, null)
      );
      expect(events.length).to.eq(1);
      const logDescription = royaltyRegistry.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionRoyaltyUpdated');
      expect(logDescription.args.collection).to.eq(testNFT.address);
      expect(logDescription.args.royaltyPercentage).to.eq(10);
      expect(logDescription.args.recipient).to.eq(await deployer.getAddress());
    });

    it('should revert if not called by the contract owner or collection', async () => {
      await expect(
        royaltyRegistry
          .connect(otherUser)
          .setRoyalty(testNFT.address, await otherUser.getAddress(), 10)
      ).eventually.rejectedWith(
        revert`setRoyalty must be called as owner or collection`
      );
    });
  });
});
