import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CollectionOffersV1,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCollectionOffersV1,
  deployRoyaltyEngine,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  mintMultipleERC721Tokens,
  proposeModule,
  registerModule,
  revert,
  toRoundedNumber,
  THOUSANDTH_ETH,
  TENTH_ETH,
  ONE_HALF_ETH,
  ONE_ETH,
  TWO_ETH,
  THREE_ETH,
  FIVE_ETH,
  NINE_ETH,
  TEN_ETH,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('CollectionOffersV1', () => {
  let collectionOffers: CollectionOffersV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let weth: WETH;
  let deployer: Signer;
  let finder: Signer;
  let buyer: Signer;
  let buyer2: Signer;
  let buyer3: Signer;
  let buyer4: Signer;
  let buyer5: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    finder = signers[1];
    buyer = signers[2];
    buyer2 = signers[3];
    buyer3 = signers[4];
    buyer4 = signers[5];
    buyer5 = signers[6];

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
    royaltyEngine = await deployRoyaltyEngine();

    collectionOffers = await deployCollectionOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      weth.address
    );

    await proposeModule(proposalManager, collectionOffers.address);
    await registerModule(proposalManager, collectionOffers.address);

    await approvalManager.setApprovalForModule(collectionOffers.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(collectionOffers.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createCollectionOffer', () => {
    it('should create an offer for a NFT collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const offer = await collectionOffers.offers(zoraV1.address, 1);
      expect(offer.buyer).to.eq(await buyer.getAddress());
      expect(offer.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer.prevId.toNumber()).to.eq(0);
      expect(offer.nextId.toNumber()).to.eq(0);

      const floorOfferId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(floorOfferId.toNumber()).to.eq(1);
      expect(floorOfferAmount.toString()).to.eq(ONE_ETH.toString());

      const ceilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const ceilingOfferAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );
      expect(ceilingOfferId.toNumber()).to.eq(1);
      expect(ceilingOfferAmount.toString()).to.eq(ONE_ETH.toString());
    });

    it('should create a second, ceiling offer for a NFT collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);

      expect(offer1.prevId.toNumber()).to.eq(0);
      expect(offer1.nextId.toNumber()).to.eq(2);

      expect(offer2.buyer).to.eq(await buyer2.getAddress());
      expect(offer2.amount.toString()).to.eq(TWO_ETH.toString());

      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(0);

      const floorOfferId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(floorOfferId.toNumber()).to.eq(1);
      expect(floorOfferAmount.toString()).to.eq(ONE_ETH.toString());

      const ceilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const ceilingOfferAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );
      expect(ceilingOfferId.toNumber()).to.eq(2);
      expect(ceilingOfferAmount.toString()).to.eq(TWO_ETH.toString());
    });

    it('should create a third, floor offer for a NFT collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      const floorOfferId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(floorOfferId.toNumber()).to.eq(3);
      expect(floorOfferAmount.toString()).to.eq(ONE_HALF_ETH.toString());

      const ceilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const ceilingOfferAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );
      expect(ceilingOfferId.toNumber()).to.eq(2);
      expect(ceilingOfferAmount.toString()).to.eq(TWO_ETH.toString());

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);

      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(2);

      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(0);

      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);
    });

    it('should create a fourth, middle offer for a NFT collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });
      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      const floorOfferId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(floorOfferId.toNumber()).to.eq(3);
      expect(floorOfferAmount.toString()).to.eq(ONE_HALF_ETH.toString());

      const ceilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const ceilingOfferAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );
      expect(ceilingOfferId.toNumber()).to.eq(2);
      expect(ceilingOfferAmount.toString()).to.eq(TEN_ETH.toString());

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);

      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(4);

      expect(offer2.prevId.toNumber()).to.eq(4);
      expect(offer2.nextId.toNumber()).to.eq(0);

      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer4.prevId.toNumber()).to.eq(1);
      expect(offer4.nextId.toNumber()).to.eq(2);
    });

    it('should create a fifth, equal middle offer for an NFT collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      await collectionOffers
        .connect(buyer5)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(5);

      expect(offer2.prevId.toNumber()).to.eq(4);
      expect(offer2.nextId.toNumber()).to.eq(0);

      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer4.prevId.toNumber()).to.eq(5);
      expect(offer4.nextId.toNumber()).to.eq(2);

      expect(offer5.prevId.toNumber()).to.eq(1);
      expect(offer5.nextId.toNumber()).to.eq(4);
    });

    it('should revert creating an offer without attaching funds', async () => {
      await expect(
        collectionOffers.connect(buyer).createCollectionOffer(zoraV1.address)
      ).eventually.rejectedWith(
        revert`createCollectionOffer msg value must be greater than 0`
      );
    });

    it('should emit a CollectionOfferCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      const events = await collectionOffers.queryFilter(
        collectionOffers.filters.CollectionOfferCreated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = collectionOffers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
    });
  });

  describe('#setCollectionOfferAmount', () => {
    // 3 -- 1 -- 5 -- 4 -- 2
    beforeEach(async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      await collectionOffers
        .connect(buyer5)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });
    });

    it('should increase a collection floor offer', async () => {
      await collectionOffers
        .connect(buyer3)
        .setCollectionOfferAmount(zoraV1.address, 3, ONE_ETH, {
          value: ONE_HALF_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer1.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(5);

      expect(offer2.amount.toString()).to.eq(TEN_ETH.toString());
      expect(offer2.prevId.toNumber()).to.eq(4);
      expect(offer2.nextId.toNumber()).to.eq(0);

      expect(offer3.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer4.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer4.prevId.toNumber()).to.eq(5);
      expect(offer4.nextId.toNumber()).to.eq(2);

      expect(offer5.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer5.prevId.toNumber()).to.eq(1);
      expect(offer5.nextId.toNumber()).to.eq(4);
    });

    it('should increase a middle collection offer', async () => {
      await collectionOffers
        .connect(buyer5)
        .setCollectionOfferAmount(zoraV1.address, 5, FIVE_ETH, {
          value: TWO_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer1.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(4);

      expect(offer2.amount.toString()).to.eq(TEN_ETH.toString());
      expect(offer2.prevId.toNumber()).to.eq(5);
      expect(offer2.nextId.toNumber()).to.eq(0);

      expect(offer3.amount.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer4.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer4.prevId.toNumber()).to.eq(1);
      expect(offer4.nextId.toNumber()).to.eq(5);

      expect(offer5.amount.toString()).to.eq(FIVE_ETH.toString());
      expect(offer5.prevId.toNumber()).to.eq(4);
      expect(offer5.nextId.toNumber()).to.eq(2);
    });

    it('should increase a collection offer and move it behind any equal offers', async () => {
      // 3 -- 1 -- 5 -- 4 -- 2
      await collectionOffers
        .connect(buyer)
        .setCollectionOfferAmount(zoraV1.address, 1, TEN_ETH, {
          value: NINE_ETH,
        });

      // 3 -- 5 -- 4 -- 1 -- 2
      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer3.amount.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(5);

      expect(offer5.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer5.prevId.toNumber()).to.eq(3);
      expect(offer5.nextId.toNumber()).to.eq(4);

      expect(offer4.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer4.prevId.toNumber()).to.eq(5);
      expect(offer4.nextId.toNumber()).to.eq(1);

      expect(offer1.amount.toString()).to.eq(TEN_ETH.toString());
      expect(offer1.prevId.toNumber()).to.eq(4);
      expect(offer1.nextId.toNumber()).to.eq(2);

      expect(offer2.amount.toString()).to.eq(TEN_ETH.toString());
      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(0);
    });

    it('should decrease a collection offer and move it behind any equal offers', async () => {
      // 3 -- 1 -- 5 -- 4 -- 2
      await collectionOffers
        .connect(buyer2)
        .setCollectionOfferAmount(zoraV1.address, 2, THREE_ETH);

      // 3 -- 1 -- 2 -- 5 -- 4
      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer3.amount.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer1.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(2);

      expect(offer2.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(5);

      expect(offer5.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer5.prevId.toNumber()).to.eq(2);
      expect(offer5.nextId.toNumber()).to.eq(4);

      expect(offer4.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer4.prevId.toNumber()).to.eq(5);
      expect(offer4.nextId.toNumber()).to.eq(0);
    });

    it('should decrease a collection offer', async () => {
      // 3 -- 1 -- 5 -- 4 -- 2
      await collectionOffers
        .connect(buyer2)
        .setCollectionOfferAmount(zoraV1.address, 2, TWO_ETH);
      // 3 -- 1 -- 2 -- 5 -- 4
      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);
      const offer4 = await collectionOffers.offers(zoraV1.address, 4);
      const offer5 = await collectionOffers.offers(zoraV1.address, 5);

      expect(offer3.amount.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(offer3.prevId.toNumber()).to.eq(0);
      expect(offer3.nextId.toNumber()).to.eq(1);

      expect(offer1.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer1.prevId.toNumber()).to.eq(3);
      expect(offer1.nextId.toNumber()).to.eq(2);

      expect(offer2.amount.toString()).to.eq(TWO_ETH.toString());
      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(5);

      expect(offer5.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer5.prevId.toNumber()).to.eq(2);
      expect(offer5.nextId.toNumber()).to.eq(4);

      expect(offer4.amount.toString()).to.eq(THREE_ETH.toString());
      expect(offer4.prevId.toNumber()).to.eq(5);
      expect(offer4.nextId.toNumber()).to.eq(0);
    });

    it('should emit a CollectionOfferPriceUpdated event', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const block = await ethers.provider.getBlockNumber();

      await collectionOffers
        .connect(buyer)
        .setCollectionOfferAmount(zoraV1.address, 1, TWO_ETH, {
          value: ONE_ETH,
        });

      const events = await collectionOffers.queryFilter(
        collectionOffers.filters.CollectionOfferPriceUpdated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = collectionOffers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferPriceUpdated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
      expect(logDescription.args.offer.amount.toString()).to.eq(
        TWO_ETH.toString()
      );
    });
  });

  describe('#cancelCollectionOffer', () => {
    beforeEach(async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
    });

    it('should should cancel a collection offer', async () => {
      const beforeFloorOfferId = await collectionOffers.floorOfferId(
        zoraV1.address
      );
      const beforeFloorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(beforeFloorOfferId.toNumber()).to.eq(1);
      expect(beforeFloorOfferAmount.toString()).to.eq(ONE_ETH.toString());

      const beforeCeilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const beforeCeilingOfferAmount =
        await collectionOffers.ceilingOfferAmount(zoraV1.address);
      expect(beforeCeilingOfferId.toNumber()).to.eq(1);
      expect(beforeCeilingOfferAmount.toString()).to.eq(ONE_ETH.toString());

      await collectionOffers
        .connect(buyer)
        .cancelCollectionOffer(zoraV1.address, 1);

      const afterFloorOfferId = await collectionOffers.floorOfferId(
        zoraV1.address
      );
      const afterFloorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      expect(afterFloorOfferId.toNumber()).to.eq(0);
      expect(afterFloorOfferAmount.toString()).to.eq('0');

      const afterCeilingOfferId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const afterCeilingOfferAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );
      expect(afterCeilingOfferId.toNumber()).to.eq(0);
      expect(afterCeilingOfferAmount.toString()).to.eq('0');
    });

    it('should revert canceling an inactive offer', async () => {
      await collectionOffers
        .connect(buyer)
        .cancelCollectionOffer(zoraV1.address, 1);

      await expect(
        collectionOffers.connect(buyer).cancelCollectionOffer(zoraV1.address, 1)
      ).eventually.rejectedWith(
        revert`cancelCollectionOffer must be active offer`
      );
    });

    it('should emit a CollectionOfferCanceled event', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const block = await ethers.provider.getBlockNumber();

      await collectionOffers
        .connect(buyer)
        .cancelCollectionOffer(zoraV1.address, 1);

      const events = await collectionOffers.queryFilter(
        collectionOffers.filters.CollectionOfferCanceled(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = collectionOffers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferCanceled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
      expect(logDescription.args.offer.amount.toString()).to.eq(
        ONE_ETH.toString()
      );
    });
  });

  describe('#fillCollectionOffer', () => {
    beforeEach(async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      await collectionOffers
        .connect(buyer5)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });
    });
    it('should fill a collection ceiling offer', async () => {
      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        THREE_ETH, // seller specifies 3 ETH minimum amount willing to accept
        await finder.getAddress()
      );

      // Offer book fills 10 ETH offer
      expect(await zoraV1.ownerOf(0)).to.eq(await buyer2.getAddress());

      const collectionCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const collectionCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(collectionCeilingId.toString()).to.eq('4');
      expect(collectionCeilingAmount.toString()).to.eq(THREE_ETH.toString());
    });

    it('should emit a CollectionOfferFilled event', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const block = await ethers.provider.getBlockNumber();

      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const events = await collectionOffers.queryFilter(
        collectionOffers.filters.CollectionOfferFilled(null, null, null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = collectionOffers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CollectionOfferFilled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
      expect(logDescription.args.offer.amount.toString()).to.eq(
        ONE_ETH.toString()
      );
      expect(logDescription.args.finder).to.eq(await finder.getAddress());
      expect(logDescription.args.seller).to.eq(await deployer.getAddress());
    });
  });

  describe('#_addOffer', () => {
    it('should mark a first collection offer the floor and ceiling', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const floorId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const ceilingId = await collectionOffers.ceilingOfferId(zoraV1.address);
      const ceilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(floorId.toNumber()).to.eq(1);
      expect(floorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(ceilingId.toNumber()).to.eq(1);
      expect(ceilingAmount.toString()).to.eq(ONE_ETH.toString());
    });

    it('should set the neighbors of a first collection offer to zero', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const offer = await collectionOffers.offers(zoraV1.address, 1);

      expect(offer.prevId.toNumber()).to.eq(0);
      expect(offer.nextId.toNumber()).to.eq(0);
    });

    it('should set a second, increased offer as the new ceiling', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const floorId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const ceilingId = await collectionOffers.ceilingOfferId(zoraV1.address);
      const ceilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(floorId.toNumber()).to.eq(1);
      expect(floorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(ceilingId.toNumber()).to.eq(2);
      expect(ceilingAmount.toString()).to.eq(TWO_ETH.toString());
    });

    it('should set the apt pointers after a second, increased offer', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);

      expect(offer1.prevId.toNumber()).to.eq(0);
      expect(offer1.nextId.toNumber()).to.eq(2);
      expect(offer2.prevId.toNumber()).to.eq(1);
      expect(offer2.nextId.toNumber()).to.eq(0);
    });

    it('should set a second, decreased offer as the new floor', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      const floorId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const ceilingId = await collectionOffers.ceilingOfferId(zoraV1.address);
      const ceilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(floorId.toNumber()).to.eq(2);
      expect(floorAmount.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(ceilingId.toNumber()).to.eq(1);
      expect(ceilingAmount.toString()).to.eq(ONE_ETH.toString());
    });

    it('should set the apt pointers after a second, decreased offer', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_HALF_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);

      expect(offer1.prevId.toNumber()).to.eq(2);
      expect(offer1.nextId.toNumber()).to.eq(0);
      expect(offer2.prevId.toNumber()).to.eq(0);
      expect(offer2.nextId.toNumber()).to.eq(1);
    });

    it('should set a third, middle offer between the floor and ceiling', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const floorId = await collectionOffers.floorOfferId(zoraV1.address);
      const floorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const ceilingId = await collectionOffers.ceilingOfferId(zoraV1.address);
      const ceilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(floorId.toNumber()).to.eq(1);
      expect(floorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(ceilingId.toNumber()).to.eq(2);
      expect(ceilingAmount.toString()).to.eq(THREE_ETH.toString());
    });

    it('should set the apt pointers after a third, middle offer', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const offer1 = await collectionOffers.offers(zoraV1.address, 1);
      const offer2 = await collectionOffers.offers(zoraV1.address, 2);
      const offer3 = await collectionOffers.offers(zoraV1.address, 3);

      expect(offer1.prevId.toNumber()).to.eq(0);
      expect(offer1.nextId.toNumber()).to.eq(3);
      expect(offer2.prevId.toNumber()).to.eq(3);
      expect(offer2.nextId.toNumber()).to.eq(0);
      expect(offer3.prevId.toNumber()).to.eq(1);
      expect(offer3.nextId.toNumber()).to.eq(2);
    });
  });

  describe('#_updateOffer', () => {
    it('should update both floor and ceiling amounts after increasing the only offer for a collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      const beforeFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const beforeFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const beforeCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const beforeCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      await collectionOffers
        .connect(buyer)
        .setCollectionOfferAmount(zoraV1.address, 1, TWO_ETH, {
          value: ONE_ETH,
        });

      const afterFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const afterFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const afterCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const afterCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(beforeFloorId.toNumber()).to.eq(1);
      expect(beforeFloorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(beforeCeilingId.toNumber()).to.eq(1);
      expect(beforeCeilingAmount.toString()).to.eq(ONE_ETH.toString());

      expect(afterFloorId.toNumber()).to.eq(1);
      expect(afterFloorAmount.toString()).to.eq(TWO_ETH.toString());
      expect(afterCeilingId.toNumber()).to.eq(1);
      expect(afterCeilingAmount.toString()).to.eq(TWO_ETH.toString());
    });

    it('should update the collection ceiling after a ceiling offer increase', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const beforeCeilingOffer = await collectionOffers.offers(
        zoraV1.address,
        2
      );
      const beforeCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const beforeCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      await collectionOffers
        .connect(buyer2)
        .setCollectionOfferAmount(zoraV1.address, 2, THREE_ETH, {
          value: ONE_ETH,
        });

      const afterCeilingOffer = await collectionOffers.offers(
        zoraV1.address,
        2
      );

      const afterCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const afterCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(beforeCeilingOffer.prevId.toNumber()).to.eq(1);
      expect(beforeCeilingOffer.nextId.toNumber()).to.eq(0);
      expect(afterCeilingOffer.prevId.toNumber()).to.eq(1);
      expect(afterCeilingOffer.nextId.toNumber()).to.eq(0);

      expect(beforeCeilingId.toNumber()).to.eq(2);
      expect(beforeCeilingAmount.toString()).to.eq(TWO_ETH.toString());
      expect(afterCeilingId.toNumber()).to.eq(2);
      expect(afterCeilingAmount.toString()).to.eq(THREE_ETH.toString());
    });

    it('should update the collection floor after a floor offer decrease', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const beforeFloorOffer = await collectionOffers.offers(zoraV1.address, 1);
      const beforeFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const beforeFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );

      await collectionOffers
        .connect(buyer)
        .setCollectionOfferAmount(zoraV1.address, 1, ONE_HALF_ETH);

      const afterFloorOffer = await collectionOffers.offers(zoraV1.address, 1);
      const afterFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const afterFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );

      expect(beforeFloorOffer.prevId.toNumber()).to.eq(0);
      expect(beforeFloorOffer.nextId.toNumber()).to.eq(2);
      expect(afterFloorOffer.prevId.toNumber()).to.eq(0);
      expect(afterFloorOffer.nextId.toNumber()).to.eq(2);

      expect(beforeFloorId.toNumber()).to.eq(1);
      expect(beforeFloorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(afterFloorId.toNumber()).to.eq(1);
      expect(afterFloorAmount.toString()).to.eq(ONE_HALF_ETH.toString());
    });

    it('should update a middle offer in place', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });
      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      const beforeOffer = await collectionOffers.offers(zoraV1.address, 3);

      await collectionOffers
        .connect(buyer3)
        .setCollectionOfferAmount(zoraV1.address, 3, THREE_ETH, {
          value: ONE_ETH,
        });

      const afterOffer = await collectionOffers.offers(zoraV1.address, 3);

      expect(beforeOffer.prevId.toNumber()).to.eq(1);
      expect(beforeOffer.nextId.toNumber()).to.eq(2);
      expect(afterOffer.prevId.toNumber()).to.eq(1);
      expect(afterOffer.nextId.toNumber()).to.eq(2);

      expect(beforeOffer.amount.toString()).to.eq(TWO_ETH.toString());
      expect(afterOffer.amount.toString()).to.eq(THREE_ETH.toString());
    });

    it('should update and relocate an offer to its apt location', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });

      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      const beforeFloorOfferId = await collectionOffers.floorOfferId(
        zoraV1.address
      );
      const beforeFloorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const beforeOffer1 = await collectionOffers.offers(zoraV1.address, 1);

      await collectionOffers
        .connect(buyer)
        .setCollectionOfferAmount(zoraV1.address, 1, TEN_ETH, {
          value: NINE_ETH,
        });

      const afterFloorOfferId = await collectionOffers.floorOfferId(
        zoraV1.address
      );
      const afterFloorOfferAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const afterOffer1 = await collectionOffers.offers(zoraV1.address, 1);

      expect(beforeFloorOfferId.toNumber()).to.eq(1);
      expect(beforeFloorOfferAmount.toString()).to.eq(ONE_ETH.toString());

      expect(afterFloorOfferId.toNumber()).to.eq(2);
      expect(afterFloorOfferAmount.toString()).to.eq(TWO_ETH.toString());

      expect(beforeOffer1.prevId.toNumber()).to.eq(0);
      expect(beforeOffer1.nextId.toNumber()).to.eq(2);
      expect(beforeOffer1.amount.toString()).to.eq(ONE_ETH.toString());

      expect(afterOffer1.prevId.toNumber()).to.eq(3);
      expect(afterOffer1.nextId.toNumber()).to.eq(0);
      expect(afterOffer1.amount.toString()).to.eq(TEN_ETH.toString());
    });
  });

  describe('#_removeOffer', () => {
    it('should remove the only offer for a collection', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });

      const beforeFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const beforeFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const beforeCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const beforeCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(beforeFloorId.toNumber()).to.eq(1);
      expect(beforeFloorAmount.toString()).to.eq(ONE_ETH.toString());
      expect(beforeCeilingId.toNumber()).to.eq(1);
      expect(beforeCeilingAmount.toString()).to.eq(ONE_ETH.toString());

      await collectionOffers
        .connect(buyer)
        .cancelCollectionOffer(zoraV1.address, 1);

      const afterFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const afterFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );
      const afterCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const afterCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(afterFloorId.toString()).to.eq('0');
      expect(afterFloorAmount.toString()).to.eq('0');
      expect(afterCeilingId.toString()).to.eq('0');
      expect(afterCeilingAmount.toString()).to.eq('0');

      const offer = await collectionOffers.offers(zoraV1.address, 1);

      expect(offer.active).to.eq(false);
      expect(offer.buyer.toString()).to.eq(
        '0x0000000000000000000000000000000000000000'
      );
      expect(offer.amount.toString()).to.eq('0');
      expect(offer.nextId.toNumber()).to.eq(0);
      expect(offer.prevId.toNumber()).to.eq(0);
    });

    it('should remove and update the collection floor', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });
      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });

      const beforeFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const beforeFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );

      expect(beforeFloorId.toNumber()).to.eq(1);
      expect(beforeFloorAmount.toString()).to.eq(ONE_ETH.toString());

      await collectionOffers
        .connect(buyer)
        .cancelCollectionOffer(zoraV1.address, 1);

      const afterFloorId = await collectionOffers.floorOfferId(zoraV1.address);
      const afterFloorAmount = await collectionOffers.floorOfferAmount(
        zoraV1.address
      );

      expect(afterFloorId.toNumber()).to.eq(2);
      expect(afterFloorAmount.toString()).to.eq(TWO_ETH.toString());
    });

    it('should remove and update the neighbors of a middle offer', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });
      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });
      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      const beforeOffer2 = await collectionOffers.offers(zoraV1.address, 2);
      const beforeOffer3 = await collectionOffers.offers(zoraV1.address, 3);
      const beforeOffer4 = await collectionOffers.offers(zoraV1.address, 4);

      expect(beforeOffer2.nextId.toNumber()).to.eq(3);
      expect(beforeOffer3.prevId.toNumber()).to.eq(2);
      expect(beforeOffer3.nextId.toNumber()).to.eq(4);
      expect(beforeOffer4.prevId.toNumber()).to.eq(3);

      await collectionOffers
        .connect(buyer3)
        .cancelCollectionOffer(zoraV1.address, 3);

      const afterOffer2 = await collectionOffers.offers(zoraV1.address, 2);
      const afterOffer4 = await collectionOffers.offers(zoraV1.address, 4);

      expect(afterOffer2.nextId.toNumber()).to.eq(4);
      expect(afterOffer4.prevId.toNumber()).to.eq(2);
    });
  });

  describe('#_getMatchingOffer', () => {
    it('should fill a ceiling offer and update the collection ceiling', async () => {
      await collectionOffers
        .connect(buyer)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
      await collectionOffers
        .connect(buyer2)
        .createCollectionOffer(zoraV1.address, {
          value: TWO_ETH,
        });
      await collectionOffers
        .connect(buyer3)
        .createCollectionOffer(zoraV1.address, {
          value: THREE_ETH,
        });
      await collectionOffers
        .connect(buyer4)
        .createCollectionOffer(zoraV1.address, {
          value: TEN_ETH,
        });

      const beforeCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const beforeCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(beforeCeilingId.toNumber()).to.eq(4);
      expect(beforeCeilingAmount.toString()).to.eq(TEN_ETH.toString());

      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        THREE_ETH,
        await finder.getAddress()
      );

      const afterCeilingId = await collectionOffers.ceilingOfferId(
        zoraV1.address
      );
      const afterCeilingAmount = await collectionOffers.ceilingOfferAmount(
        zoraV1.address
      );

      expect(afterCeilingId.toNumber()).to.eq(3);
      expect(afterCeilingAmount.toString()).to.eq(THREE_ETH.toString());
    });
  });
});
