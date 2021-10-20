import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  OffersV1,
  TestErc721,
  CollectionRoyaltyRegistryV1,
  Weth,
} from '../../../typechain';

import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployTestERC271,
  deployWETH,
  deployRoyaltyRegistry,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  mintERC721Token,
  ONE_ETH,
  ONE_HALF_ETH,
  proposeModule,
  registerModule,
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  THREE_ETH,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
chai.use(asPromised);

describe('OffersV1', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let weth: Weth;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;
  let royaltyRegistry: CollectionRoyaltyRegistryV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[2];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

    testERC721 = await deployTestERC271();
    weth = await deployWETH();

    const proposalManager = await deployZoraProposalManager(
      await deployer.getAddress()
    );
    const approvalManager = await deployZoraModuleApprovalsManager(
      proposalManager.address
    );

    erc20TransferHelper = await deployERC20TransferHelper(
      approvalManager.address
    );
    erc721TransferHelper = await deployERC721TransferHelper(
      approvalManager.address
    );
    royaltyRegistry = await deployRoyaltyRegistry();

    offers = await deployOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyRegistry.address,
      zoraV1.address,
      weth.address
    );

    await proposeModule(proposalManager, offers.address);
    await registerModule(proposalManager, offers.address);

    await approvalManager.setApprovalForModule(offers.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(offers.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  /**
   * NFT offers
   */

  describe('#createNFTOffer', () => {
    it('should create an offer for an NFT', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      const offer = await offers.nftOffers(1);

      expect(offer.buyer).to.eq(await buyer.getAddress());
      expect(offer.tokenContract).to.eq(zoraV1.address);
      expect(offer.tokenID.toNumber()).to.eq(0);
      expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
      expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
      expect(offer.status).to.eq(0);

      expect(
        (await offers.userToNFTOffers(await buyer.getAddress(), 0)).toNumber()
      ).to.eq(1);

      expect(
        await offers.userHasActiveNFTOffer(
          await buyer.getAddress(),
          zoraV1.address,
          0
        )
      ).to.eq(true);

      expect((await offers.nftToOffers(zoraV1.address, 0, 0)).toNumber()).to.eq(
        1
      );
    });

    it('should revert creating an offer for an NFT owned', async () => {
      const owner = await zoraV1.signer;
      await expect(
        offers
          .connect(owner)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`createNFTOffer cannot make offer on NFT you own`
      );
    });

    it('should revert creating a second active offer for a NFT', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            TWO_ETH,
            ethers.constants.AddressZero,
            { value: TWO_ETH }
          )
      ).eventually.rejectedWith(
        revert`createNFTOffer must update or cancel existing offer`
      );
    });

    it('should revert creating an offer without attaching associated funds', async () => {
      await expect(
        offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            {
              value: ONE_HALF_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should emit an NFTOfferCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      const events = await offers.queryFilter(
        offers.filters.NFTOfferCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
    });
  });

  describe('#updateNFTPrice', () => {
    it('should increase an offer price', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(buyer)
        .updateNFTPrice(1, TWO_ETH, { value: ONE_ETH });
      expect((await (await offers.nftOffers(1)).offerPrice).toString()).to.eq(
        TWO_ETH.toString()
      );
    });

    it('should decrease an offer price', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.connect(buyer).updateNFTPrice(1, ONE_HALF_ETH);
      expect((await (await offers.nftOffers(1)).offerPrice).toString()).to.eq(
        ONE_HALF_ETH.toString()
      );
    });

    it('should revert user increasing an offer they did not create', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(otherUser).updateNFTPrice(1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(
        revert`updateNFTPrice must be buyer from original offer`
      );
    });

    it('should revert user decreasing an offer they did not create', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(otherUser).updateNFTPrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`updateNFTPrice must be buyer from original offer`
      );
    });

    it('should revert increasing an offer without attaching funds', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(buyer).updateNFTPrice(1, TWO_ETH)
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should revert updating an inactive offer', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptNFTOffer(1);

      await expect(
        offers.connect(buyer).updateNFTPrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(revert`updateNFTPrice must be active offer`);
    });

    it('should emit an NFTOfferUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(buyer)
        .updateNFTPrice(1, TWO_ETH, { value: ONE_ETH });

      const events = await offers.queryFilter(
        offers.filters.NFTOfferUpdated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferUpdated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.offerPrice.toString()).to.eq(
        TWO_ETH.toString()
      );
    });
  });

  describe('#cancelNFTOffer', () => {
    it('should cancel an active NFT offer', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelNFTOffer(1);
      expect(await (await offers.nftOffers(1)).status).to.eq(1);
    });

    it('should revert canceling an inactive offer', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptNFTOffer(1);
      await expect(
        offers.connect(buyer).cancelNFTOffer(1)
      ).eventually.rejectedWith(revert`cancelNFTOffer must be active offer`);
    });

    it('should revert canceling an offer not originally made', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers.connect(otherUser).cancelNFTOffer(1)
      ).eventually.rejectedWith(
        revert`cancelNFTOffer must be buyer from original offer`
      );
    });

    it('should create new offer on same NFT after canceling', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelNFTOffer(1);
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          TENTH_ETH,
          ethers.constants.AddressZero,
          {
            value: TENTH_ETH,
          }
        );
      expect((await (await offers.nftOffers(2)).offerPrice).toString()).to.eq(
        TENTH_ETH.toString()
      );
    });

    it('should emit an NFTOfferCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelNFTOffer(1);
      const events = await offers.queryFilter(
        offers.filters.NFTOfferCanceled(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferCanceled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(1);
    });
  });

  describe('#acceptNFTOffer', () => {
    it('should accept an offer', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.acceptNFTOffer(1);

      expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
    });

    it('should revert accepting an inactive offer', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.acceptNFTOffer(1);

      await expect(offers.acceptNFTOffer(1)).eventually.rejectedWith(
        revert`acceptNFTOffer must be active offer`
      );
    });

    it('should revert accepting an offer from non-token holder', async () => {
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers.connect(otherUser).acceptNFTOffer(1)
      ).eventually.rejectedWith(
        revert`acceptNFTOffer must own token associated with offer`
      );
    });

    it('should emit an NFTOfferAccepted event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptNFTOffer(1);
      const events = await offers.queryFilter(
        offers.filters.NFTOfferAccepted(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferAccepted');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(2);
    });
  });

  /**
   * Collection offers
   */

  describe('#createCollectionOffer', () => {
    it('should create an offer for a NFT collection', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      const offer = await offers.collectionOffers(1);

      expect(offer.buyer).to.eq(await buyer.getAddress());
      expect(offer.tokenContract).to.eq(zoraV1.address);
      expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
      expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
      expect(offer.status).to.eq(0);

      expect(
        (
          await offers.userToCollectionOffers(await buyer.getAddress(), 0)
        ).toNumber()
      ).to.eq(1);

      expect(
        await offers.userHasActiveCollectionOffer(
          await buyer.getAddress(),
          zoraV1.address
        )
      ).to.eq(true);

      expect(
        (await offers.collectionToOffers(zoraV1.address, 0)).toNumber()
      ).to.eq(1);
    });

    it('should revert a second active offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            TWO_ETH,
            ethers.constants.AddressZero,
            { value: TWO_ETH }
          )
      ).eventually.rejectedWith(
        revert`createCollectionOffer must update or cancel existing offer`
      );
    });

    it('should revert creating an offer without attaching associated funds', async () => {
      await expect(
        offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            {
              value: ONE_HALF_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should emit an OfferCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      const events = await offers.queryFilter(
        offers.filters.CollectionOfferCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
    });
  });

  describe('#updateCollectionPrice', () => {
    it('should increase a collection offer price', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(buyer)
        .updateCollectionPrice(1, TWO_ETH, { value: ONE_ETH });
      expect(
        (await (await offers.collectionOffers(1)).offerPrice).toString()
      ).to.eq(TWO_ETH.toString());
    });

    it('should decrease an offer price', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.connect(buyer).updateCollectionPrice(1, ONE_HALF_ETH);
      expect(
        (await (await offers.collectionOffers(1)).offerPrice).toString()
      ).to.eq(ONE_HALF_ETH.toString());
    });

    it('should revert user increasing an offer they did not create', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers
          .connect(otherUser)
          .updateCollectionPrice(1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(
        revert`updateCollectionPrice must be buyer from original offer`
      );
    });

    it('should revert user decreasing an offer they did not create', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(otherUser).updateCollectionPrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`updateCollectionPrice must be buyer from original offer`
      );
    });

    it('should revert increasing an offer without attaching funds', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(buyer).updateCollectionPrice(1, TWO_ETH)
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should revert updating an inactive offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptCollectionOffer(1, 0);

      await expect(
        offers.connect(buyer).updateCollectionPrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`updateCollectionPrice must be active offer`
      );
    });

    it('should emit an CollectionOfferUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(buyer)
        .updateCollectionPrice(1, TWO_ETH, { value: ONE_ETH });

      const events = await offers.queryFilter(
        offers.filters.CollectionOfferUpdated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferUpdated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.offerPrice.toString()).to.eq(
        TWO_ETH.toString()
      );
    });
  });

  describe('#cancelCollectionOffer', () => {
    it('should cancel an active collection offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelCollectionOffer(1);
      expect(await (await offers.collectionOffers(1)).status).to.eq(1);
    });

    it('should revert canceling an inactive offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptCollectionOffer(1, 0);
      await expect(
        offers.connect(buyer).cancelCollectionOffer(1)
      ).eventually.rejectedWith(
        revert`cancelCollectionOffer must be active offer`
      );
    });

    it('should revert canceling an offer not originally made', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers.connect(otherUser).cancelCollectionOffer(1)
      ).eventually.rejectedWith(
        revert`cancelCollectionOffer must be buyer from original offer`
      );
    });

    it('should create new offer on same NFT after canceling', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelCollectionOffer(1);
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          TENTH_ETH,
          ethers.constants.AddressZero,
          {
            value: TENTH_ETH,
          }
        );
      expect(
        (await (await offers.collectionOffers(2)).offerPrice).toString()
      ).to.eq(TENTH_ETH.toString());
    });

    it('should emit an CollectionOfferCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(buyer).cancelCollectionOffer(1);
      const events = await offers.queryFilter(
        offers.filters.CollectionOfferCanceled(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferCanceled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(1);
    });
  });

  describe('#acceptCollectionOffer', () => {
    it('should accept a collection offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.acceptCollectionOffer(1, 0);

      expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
    });

    it('should revert accepting an inactive collection offer', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offers.acceptCollectionOffer(1, 0);

      await expect(offers.acceptCollectionOffer(1, 0)).eventually.rejectedWith(
        revert`acceptCollectionOffer must be active offer`
      );
    });

    it('should revert accepting a collection offer from a non-collection token holder', async () => {
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers.connect(otherUser).acceptCollectionOffer(1, 0)
      ).eventually.rejectedWith(
        revert`acceptCollectionOffer must own token associated with offer`
      );
    });

    it('should emit a CollectionOfferAccepted event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(buyer)
        .createCollectionOffer(
          zoraV1.address,
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offers.acceptCollectionOffer(1, 0);
      const events = await offers.queryFilter(
        offers.filters.CollectionOfferAccepted(null, null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferAccepted');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(2);
    });
  });
});
