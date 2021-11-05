import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  OffersV1,
  TestERC721,
  CollectionRoyaltyRegistryV1,
  WETH,
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
  mintMultipleERC721Tokens,
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
  let testERC721: TestERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let otherSeller: Signer;
  let otherBuyer: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyRegistry: CollectionRoyaltyRegistryV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[2];
    finder = signers[3];
    otherSeller = signers[4];
    otherBuyer = signers[5];

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
      weth.address
    );

    await proposeModule(proposalManager, offers.address);
    await registerModule(proposalManager, offers.address);

    await approvalManager.setApprovalForModule(offers.address, true);

    await approvalManager
      .connect(otherSeller)
      .setApprovalForModule(offers.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('Collection Offers', () => {
    describe('#createCollectionOffer', () => {
      it('should create an offer for a NFT collection', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
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
            await offers.collectionOffersPerUser(await buyer.getAddress(), 0)
          ).toNumber()
        ).to.eq(1);

        expect(
          (await offers.offersPerCollection(zoraV1.address, 0)).toNumber()
        ).to.eq(1);
      });

      it('should revert creating an offer without attaching associated funds', async () => {
        await expect(
          offers
            .connect(buyer)
            .createCollectionOffer(
              zoraV1.address,
              ONE_ETH,
              ethers.constants.AddressZero,
              10,
              {
                value: ONE_HALF_ETH,
              }
            )
        ).eventually.rejectedWith(
          revert`_handleIncomingTransfer msg value less than expected amount`
        );
      });

      it('should emit an CollectionOfferCreated event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
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

    describe('#setCollectionOfferPrice', () => {
      it('should increase a collection offer price', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });
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
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers
            .connect(otherUser)
            .setCollectionOfferPrice(1, TWO_ETH, { value: TWO_ETH })
        ).eventually.rejectedWith(
          revert`setCollectionOfferPrice must be buyer from original offer`
        );
      });

      it('should revert user decreasing an offer they did not create', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers.connect(otherUser).setCollectionOfferPrice(1, ONE_HALF_ETH)
        ).eventually.rejectedWith(
          revert`setCollectionOfferPrice must be buyer from original offer`
        );
      });

      it('should revert increasing an offer without attaching funds', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers.connect(buyer).setCollectionOfferPrice(1, TWO_ETH)
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        await expect(
          offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH)
        ).eventually.rejectedWith(
          revert`setCollectionOfferPrice must be active offer`
        );
      });

      it('should emit an CollectionOfferPriceUpdated event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const events = await offers.queryFilter(
          offers.filters.CollectionOfferPriceUpdated(null, null),
          block
        );
        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('CollectionOfferPriceUpdated');
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
            10,
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
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
            10,
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
            10,
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
            10,
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
            10,
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

    describe('#fillCollectionOffer', () => {
      it('should accept a collection offer', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
      });

      it('should revert accepting a collection offer from a non-collection token holder', async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await expect(
          offers
            .connect(otherUser)
            .fillCollectionOffer(1, 0, await finder.getAddress())
        ).eventually.rejectedWith(
          revert`fillCollectionOffer must own token associated with offer`
        );
      });

      it('should emit a CollectionOfferFilled event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const events = await offers.queryFilter(
          offers.filters.CollectionOfferFilled(null, null, null, null),
          block
        );
        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('CollectionOfferFilled');
        expect(logDescription.args.id.toNumber()).to.eq(1);
        expect(logDescription.args.offer.status).to.eq(2);
      });

      it('should emit an ExchangeExecuted event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const events = await offers.queryFilter(
          offers.filters.ExchangeExecuted(null, null, null, null),
          block
        );

        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('ExchangeExecuted');
        expect(logDescription.args.userA).to.eq(await deployer.getAddress());
        expect(logDescription.args.userB).to.eq(await buyer.getAddress());

        expect(logDescription.args.a.tokenContract).to.eq(
          await (
            await offers.collectionOffers(1)
          ).tokenContract
        );
        expect(logDescription.args.b.tokenContract).to.eq(
          ethers.constants.AddressZero
        );
      });
    });
  });

  describe('NFT Offers', () => {
    describe('#createNFTOffer', () => {
      it('should create an offer for an NFT', async () => {
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        const offer = await offers.nftOffers(1);

        expect(offer.buyer).to.eq(await buyer.getAddress());
        expect(offer.tokenContract).to.eq(zoraV1.address);
        expect(offer.tokenId.toNumber()).to.eq(0);
        expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
        expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
        expect(offer.status).to.eq(0);

        expect(
          (
            await offers.nftOffersPerUser(await buyer.getAddress(), 0)
          ).toNumber()
        ).to.eq(1);

        expect(
          (await offers.offersPerNFT(zoraV1.address, 0, 0)).toNumber()
        ).to.eq(1);
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
              10,
              {
                value: ONE_ETH,
              }
            )
        ).eventually.rejectedWith(
          revert`createNFTOffer cannot make offer on NFT you own`
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
              10,
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
            10,
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

    describe('#setNFTOfferPrice', () => {
      it('should increase an offer price', async () => {
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });
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
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers
            .connect(otherUser)
            .setNFTOfferPrice(1, TWO_ETH, { value: TWO_ETH })
        ).eventually.rejectedWith(
          revert`setNFTOfferPrice must be buyer from original offer`
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers.connect(otherUser).setNFTOfferPrice(1, ONE_HALF_ETH)
        ).eventually.rejectedWith(
          revert`setNFTOfferPrice must be buyer from original offer`
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await expect(
          offers.connect(buyer).setNFTOfferPrice(1, TWO_ETH)
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillNFTOffer(1, await finder.getAddress());

        await expect(
          offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH)
        ).eventually.rejectedWith(
          revert`setNFTOfferPrice must be active offer`
        );
      });

      it('should emit an NFTOfferPriceUpdated event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const events = await offers.queryFilter(
          offers.filters.NFTOfferPriceUpdated(null, null),
          block
        );
        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('NFTOfferPriceUpdated');
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
            10,
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
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillNFTOffer(1, await finder.getAddress());
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
            10,
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
            10,
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
            10,
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
            10,
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

    describe('#fillNFTOffer', () => {
      it('should accept an offer', async () => {
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers.fillNFTOffer(1, await finder.getAddress());

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
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers.fillNFTOffer(1, await finder.getAddress());

        await expect(
          offers.fillNFTOffer(1, await finder.getAddress())
        ).eventually.rejectedWith(revert`fillNFTOffer must be active offer`);
      });

      it('should revert accepting an offer from non-token holder', async () => {
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await expect(
          offers.connect(otherUser).fillNFTOffer(1, await finder.getAddress())
        ).eventually.rejectedWith(
          revert`fillNFTOffer must own token associated with offer`
        );
      });

      it('should emit an NFTOfferFilled event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillNFTOffer(1, await finder.getAddress());
        const events = await offers.queryFilter(
          offers.filters.NFTOfferFilled(null, null, null, null),
          block
        );
        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('NFTOfferFilled');
        expect(logDescription.args.id.toNumber()).to.eq(1);
        expect(logDescription.args.offer.status).to.eq(2);
      });

      it('should emit an ExchangeExecuted event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        await offers.fillNFTOffer(1, await finder.getAddress());
        const events = await offers.queryFilter(
          offers.filters.ExchangeExecuted(null, null, null, null),
          block
        );

        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('ExchangeExecuted');
        expect(logDescription.args.userA).to.eq(await deployer.getAddress());
        expect(logDescription.args.userB).to.eq(await buyer.getAddress());

        expect(logDescription.args.a.tokenContract).to.eq(
          await (
            await offers.nftOffers(1)
          ).tokenContract
        );
        expect(logDescription.args.b.tokenContract).to.eq(
          ethers.constants.AddressZero
        );
      });
    });
  });

  describe('NFT Group Offers', () => {
    beforeEach(async () => {
      await mintMultipleERC721Tokens(
        testERC721,
        await deployer.getAddress(),
        3
      );
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address,
        0
      );
    });

    describe('#createNFTGroupOffer', () => {
      it('should create an offer for an NFT', async () => {
        await offers
          .connect(buyer)
          .createNFTGroupOffer(
            testERC721.address,
            [1, 0, 2],
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
        const offer = await offers.nftGroupOffers(1);

        expect(offer.buyer).to.eq(await buyer.getAddress());
        expect(offer.tokenContract).to.eq(testERC721.address);
        expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
        expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
        expect(offer.status).to.eq(0);

        expect(
          (
            await offers.nftGroupOffersPerUser(await buyer.getAddress(), 0)
          ).toNumber()
        ).to.eq(1);

        expect(
          (await offers.offersPerNFTGroup(testERC721.address, 0)).toNumber()
        ).to.eq(1);
      });

      it('should revert creating an offer for an NFT owned', async () => {
        await expect(
          offers
            .connect(deployer)
            .createNFTGroupOffer(
              testERC721.address,
              [1, 0, 2],
              ONE_ETH,
              ethers.constants.AddressZero,
              10,
              {
                value: ONE_HALF_ETH,
              }
            )
        ).eventually.rejectedWith(
          revert`createNFTGroupOffer cannot make offer on NFT you own`
        );
      });

      it('should revert creating an offer without attaching associated funds', async () => {
        await expect(
          offers
            .connect(buyer)
            .createNFTGroupOffer(
              testERC721.address,
              [1, 0, 2],
              ONE_ETH,
              ethers.constants.AddressZero,
              10,
              {
                value: ONE_HALF_ETH,
              }
            )
        ).eventually.rejectedWith(
          revert`_handleIncomingTransfer msg value less than expected amount`
        );
      });

      it('should emit an NFTGroupOfferCreated event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(buyer)
          .createNFTGroupOffer(
            testERC721.address,
            [1, 0, 2],
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        const events = await offers.queryFilter(
          offers.filters.NFTGroupOfferCreated(null, null),
          block
        );

        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('NFTGroupOfferCreated');
        expect(logDescription.args.id.toNumber()).to.eq(1);
        expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
      });
    });

    describe('#setNFTGroupOfferPrice', () => {
      beforeEach(async () => {
        await offers
          .connect(buyer)
          .createNFTGroupOffer(
            testERC721.address,
            [1, 0, 2],
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
      });

      it('should increase an offer price', async () => {
        await offers
          .connect(buyer)
          .setNFTGroupOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterPrice = await (await offers.nftGroupOffers(1)).offerPrice;
        expect(afterPrice.toBigInt()).to.eq(TWO_ETH.toBigInt());
      });

      it('should decrease an offer price', async () => {
        await offers.connect(buyer).setNFTGroupOfferPrice(1, ONE_HALF_ETH);

        const afterPrice = await (await offers.nftGroupOffers(1)).offerPrice;
        expect(afterPrice.toBigInt()).to.eq(ONE_HALF_ETH.toBigInt());
      });

      it('should revert user increasing an offer they did not create', async () => {
        await expect(
          offers
            .connect(otherBuyer)
            .setNFTGroupOfferPrice(1, TWO_ETH, { value: ONE_ETH })
        ).eventually.rejectedWith(
          'setNFTGroupOfferPrice must be buyer from original offer'
        );
      });

      it('should revert user decreasing an offer they did not create ', async () => {
        await expect(
          offers.connect(otherBuyer).setNFTGroupOfferPrice(1, ONE_HALF_ETH)
        ).eventually.rejectedWith(
          'setNFTGroupOfferPrice must be buyer from original offer'
        );
      });

      it('should revert increasing an offer without attaching funds ', async () => {
        await expect(
          offers
            .connect(buyer)
            .setNFTGroupOfferPrice(1, TWO_ETH, { value: ONE_HALF_ETH })
        ).eventually.rejectedWith(
          '_handleIncomingTransfer msg value less than expected amount'
        );
      });

      it('should emit an NFTGroupOfferUpdated event', async () => {
        const block = await ethers.provider.getBlockNumber();
        await offers
          .connect(otherBuyer)
          .createNFTGroupOffer(
            testERC721.address,
            [1, 0, 2],
            TWO_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: TWO_ETH,
            }
          );
        await offers
          .connect(otherBuyer)
          .setNFTGroupOfferPrice(2, THREE_ETH, { value: ONE_ETH });

        const events = await offers.queryFilter(
          offers.filters.NFTGroupOfferPriceUpdated(null, null),
          block
        );
        expect(events.length).to.eq(1);
        const logDescription = offers.interface.parseLog(events[0]);
        expect(logDescription.name).to.eq('NFTGroupOfferPriceUpdated');
        expect(logDescription.args.id.toNumber()).to.eq(2);
        expect(logDescription.args.offer.offerPrice.toString()).to.eq(
          THREE_ETH.toString()
        );
      });
    });

    // describe('#cancelNFTGroupOffer', () => {
    //   it('should revert canceling an inactive offer', async () => {});
    //   it('should revert canceling an offer not originally made', async () => {});
    //   it('should create new offer on same NFT after canceling', async () => {});
    //   it('should emit an NFTGroupOfferCanceled event', async () => {});
    // });

    // describe('#fillNFTGroupOffer', () => {
    //   it('should accept an offer', async () => {});
    //   it('should revert accepting an inactive offer', async () => {});
    //   it('should revert accepting an offer from non-token holder', async () => {});
    //   it('should emit an NFTGroupOfferFilled event', async () => {});
    // });
  });

  describe('Collection Order Book', () => {
    beforeEach(async () => {
      await mintMultipleERC721Tokens(
        testERC721,
        await deployer.getAddress(),
        3
      );
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address,
        0
      );

      // Deployer sends token 1 from collection to otherSeller
      await testERC721.transferFrom(
        await deployer.getAddress(),
        await otherSeller.getAddress(),
        1
      );

      // OtherUser approves ZORA to transfer token
      await testERC721
        .connect(otherSeller)
        .approve(erc721TransferHelper.address, 1);
    });

    describe('#createCollectionOffer', () => {
      beforeEach(async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers
          .connect(otherBuyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
      });
      it('should store two equal offers for a NFT collection in the same location', async () => {
        const off1 = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          0
        );

        const off2 = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          1
        );

        expect(off1.toNumber()).to.eq(1);
        expect(off2.toNumber()).to.eq(2);

        const off1Index = await offers.collectionOfferToOrderBookIndex(1);
        const off2Index = await offers.collectionOfferToOrderBookIndex(2);

        expect(off1Index.toNumber()).to.eq(0);
        expect(off2Index.toNumber()).to.eq(1);
      });
    });

    describe('#setCollectionOfferPrice', () => {
      beforeEach(async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers
          .connect(otherBuyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
      });

      it('should delete offer id from old location in order book', async () => {
        const beforeIndex = await offers.collectionOfferToOrderBookIndex(1);
        expect(beforeIndex.toNumber()).to.eq(0);

        const beforeValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          0
        );
        expect(beforeValue.toNumber()).to.eq(1);

        // Update offer
        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          0
        );
        expect(afterValue.toNumber()).to.eq(0);
      });

      it('should add offer id to updated location in order book', async () => {
        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_HALF_ETH,
          0
        );

        expect(afterValue.toNumber()).to.eq(1);
      });
    });

    describe('#cancelCollectionOffer', () => {
      beforeEach(async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers
          .connect(otherBuyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
      });

      it('should update the second offer with a value of 0', async () => {
        const beforeIndex = await offers.collectionOfferToOrderBookIndex(2);
        expect(beforeIndex.toNumber()).to.eq(1);

        const beforeValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          1
        );
        expect(beforeValue.toNumber()).to.eq(2);

        await offers.connect(otherBuyer).cancelCollectionOffer(2);

        const afterIndex = await offers.collectionOfferToOrderBookIndex(2);
        expect(afterIndex.toNumber()).to.eq(0);

        const afterValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          1
        );
        expect(afterValue.toNumber()).to.eq(0);
      });
    });

    describe('#fillCollectionOffer', () => {
      beforeEach(async () => {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );

        await offers
          .connect(otherBuyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            {
              value: ONE_ETH,
            }
          );
      });

      it('should fill two equal offers', async () => {
        await offers
          .connect(deployer)
          .fillCollectionOffer(1, 0, await finder.getAddress());

        await offers
          .connect(otherSeller)
          .fillCollectionOffer(1, 1, await finder.getAddress());

        const offer1Status = await (await offers.collectionOffers(1)).status;
        expect(offer1Status.toString()).to.eq('2'); // Filled

        const offer2Status = await (await offers.collectionOffers(2)).status;
        expect(offer2Status.toString()).to.eq('2'); // Filled

        const offer1BookValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          0
        );

        expect(offer1BookValue.toNumber()).to.eq(0); // marked as inactive

        const offer2BookValue = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          1
        );

        expect(offer2BookValue.toNumber()).to.eq(0); // marked as inactive

        const collectionIndex = await offers.collectionOrderBookStartingIndex(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH
        );
        expect(collectionIndex.toNumber()).to.eq(2); // starting index is updated to 2
      });

      it('should mark first offer inactive and second offer active', async () => {
        await offers
          .connect(deployer)
          .fillCollectionOffer(1, 0, await finder.getAddress());

        const offer1Id = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          0
        );

        expect(offer1Id.toNumber()).to.eq(0);

        const offer2Id = await offers.collectionOrderBook(
          testERC721.address,
          ethers.constants.AddressZero,
          ONE_ETH,
          1
        );
        expect(offer2Id.toNumber()).to.eq(2);
      });
    });
  });
});
