import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  OffersV1,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';

import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployProtocolFeeSettings,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_ETH,
  ONE_HALF_ETH,
  proposeModule,
  registerModule,
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('OffersV1', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let weth: WETH;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[2];
    finder = signers[3];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

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
    const feeSettings = await deployProtocolFeeSettings(
      await deployer.getAddress()
    );

    offers = await deployOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
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
      const offer = await offers.offers(1);

      expect(offer.buyer).to.eq(await buyer.getAddress());
      expect(offer.tokenContract).to.eq(zoraV1.address);
      expect(offer.tokenId.toNumber()).to.eq(0);
      expect(offer.amount.toString()).to.eq(ONE_ETH.toString());
      expect(offer.currency).to.eq(ethers.constants.AddressZero);

      expect(
        (await offers.offersForNFT(zoraV1.address, 0, 0)).toNumber()
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
        revert`createNFTOffer cannot make offer on owned NFT`
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

  describe('#setNFTOfferAmount', () => {
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
        .setNFTOfferAmount(1, TWO_ETH, { value: ONE_ETH });
      expect((await (await offers.offers(1)).amount).toString()).to.eq(
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

      await offers.connect(buyer).setNFTOfferAmount(1, ONE_HALF_ETH);
      expect((await (await offers.offers(1)).amount).toString()).to.eq(
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
          .setNFTOfferAmount(1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(
        revert`setNFTOfferAmount offer must be active and caller must be original buyer`
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
        offers.connect(otherUser).setNFTOfferAmount(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`setNFTOfferAmount offer must be active and caller must be original buyer`
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
        offers.connect(buyer).setNFTOfferAmount(1, TWO_ETH)
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
        offers.connect(buyer).setNFTOfferAmount(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`setNFTOfferAmount offer must be active and caller must be original buyer`
      );
    });

    it('should emit an NFTOfferAmountUpdated event', async () => {
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
        .setNFTOfferAmount(1, TWO_ETH, { value: ONE_ETH });

      const events = await offers.queryFilter(
        offers.filters.NFTOfferAmountUpdated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferAmountUpdated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.amount.toString()).to.eq(
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
      expect((await (await offers.offers(1)).tokenContract).toString()).to.eq(
        ethers.constants.AddressZero.toString()
      );
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
      ).eventually.rejectedWith(
        revert`cancelNFTOffer offer must be active and caller must be original buyer`
      );
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
        revert`cancelNFTOffer offer must be active and caller must be original buyer`
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
      expect((await (await offers.offers(2)).amount).toString()).to.eq(
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
    });
  });

  describe('#fillNFTOffer', () => {
    it('should accept an offer', async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );

      const buyerBeforeBalance = await buyer.getBalance();
      const minterBeforeBalance = await deployer.getBalance();
      const finderBeforeBalance = await finder.getBalance();
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
      const buyerAfterBalance = await buyer.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const finderAfterBalance = await finder.getBalance();

      expect(toRoundedNumber(buyerAfterBalance)).to.be.approximately(
        toRoundedNumber(buyerBeforeBalance.sub(ONE_ETH)),
        5
      );

      expect(toRoundedNumber(minterAfterBalance)).to.be.approximately(
        toRoundedNumber(
          minterBeforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
        ),
        5
      );

      expect(toRoundedNumber(finderAfterBalance)).to.be.approximately(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(85))),
        10
      );

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
      expect(logDescription.args.seller.toString()).to.eq(
        await deployer.getAddress()
      );
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

      expect(logDescription.args.a.tokenContract).to.eq(zoraV1.address);
      expect(logDescription.args.b.tokenContract).to.eq(
        ethers.constants.AddressZero
      );
    });
  });
});
