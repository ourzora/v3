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
  TestERC721,
} from '../../../typechain';

import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployProtocolFeeSettings,
  deployRoyaltyEngine,
  deployTestERC721,
  deployWETH,
  deployZoraModuleManager,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_ETH,
  ONE_HALF_ETH,
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
  let seller: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;
  let testERC721: TestERC721;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    seller = signers[1];
    otherUser = signers[2];
    finder = signers[3];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

    weth = await deployWETH();
    testERC721 = await deployTestERC721();

    const feeSettings = await deployProtocolFeeSettings();
    const moduleManager = await deployZoraModuleManager(
      await deployer.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(moduleManager.address, testERC721.address);

    erc20TransferHelper = await deployERC20TransferHelper(
      moduleManager.address
    );
    erc721TransferHelper = await deployERC721TransferHelper(
      moduleManager.address
    );
    royaltyEngine = await deployRoyaltyEngine();

    offers = await deployOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );

    await registerModule(moduleManager, offers.address);

    await moduleManager.setApprovalForModule(offers.address, true);
    await moduleManager
      .connect(seller)
      .setApprovalForModule(offers.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createNFTOffer', () => {
    it('should create an offer for an NFT', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      const offer = await offers.offers(zoraV1.address, 0, 1);

      expect(offer.seller).to.eq(await seller.getAddress());
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
            1000,
            {
              value: ONE_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`createNFTOffer cannot place offer on own NFT`
      );
    });

    it('should revert creating an offer without attaching associated funds', async () => {
      await expect(
        offers
          .connect(seller)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            1000,
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
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
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
      expect(logDescription.args.offer.seller).to.eq(await seller.getAddress());
    });
  });

  describe('#setNFTOfferAmount', () => {
    it('should increase an offer price', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(seller)
        .setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH, { value: ONE_ETH });
      expect(
        (await (await offers.offers(zoraV1.address, 0, 1)).amount).toString()
      ).to.eq(TWO_ETH.toString());
    });

    it('should decrease an offer price', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );

      await offers
        .connect(seller)
        .setNFTOfferAmount(zoraV1.address, 0, 1, ONE_HALF_ETH);
      expect(
        (await (await offers.offers(zoraV1.address, 0, 1)).amount).toString()
      ).to.eq(ONE_HALF_ETH.toString());
    });

    it('should revert user increasing an offer they did not create', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers
          .connect(otherUser)
          .setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(revert`setNFTOfferAmount must be seller`);
    });

    it('should revert user decreasing an offer they did not create', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers
          .connect(otherUser)
          .setNFTOfferAmount(zoraV1.address, 0, 1, ONE_HALF_ETH)
      ).eventually.rejectedWith(revert`setNFTOfferAmount must be seller`);
    });

    it('should revert increasing an offer without attaching funds', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offers.connect(seller).setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH)
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should revert updating an inactive offer', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );

      await expect(
        offers
          .connect(seller)
          .setNFTOfferAmount(zoraV1.address, 0, 1, ONE_HALF_ETH)
      ).eventually.rejectedWith(revert`setNFTOfferAmount must be seller`);
    });

    it('should emit an NFTOfferAmountUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers
        .connect(seller)
        .setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH, { value: ONE_ETH });

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
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1);
      expect(
        (await (await offers.offers(zoraV1.address, 0, 1)).seller).toString()
      ).to.eq(ethers.constants.AddressZero.toString());
    });

    it('should revert canceling an inactive offer', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );
      await expect(
        offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1)
      ).eventually.rejectedWith(revert`cancelNFTOffer must be seller`);
    });

    it('should revert canceling an offer not originally made', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers.connect(otherUser).cancelNFTOffer(zoraV1.address, 0, 1)
      ).eventually.rejectedWith(revert`cancelNFTOffer must be seller`);
    });

    it('should create new offer on same NFT after canceling', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1);
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          TENTH_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: TENTH_ETH,
          }
        );
      expect(
        (await (await offers.offers(zoraV1.address, 0, 2)).amount).toString()
      ).to.eq(TENTH_ETH.toString());
    });

    it('should emit an NFTOfferCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1);
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

      const sellerBeforeBalance = await seller.getBalance();
      const minterBeforeBalance = await deployer.getBalance();
      const finderBeforeBalance = await finder.getBalance();
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );
      const sellerAfterBalance = await seller.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const finderAfterBalance = await finder.getBalance();

      expect(toRoundedNumber(sellerAfterBalance)).to.be.approximately(
        toRoundedNumber(sellerBeforeBalance.sub(ONE_ETH)),
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

      expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
    });

    it('should revert accepting an inactive offer', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );

      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );

      await expect(
        offers.fillNFTOffer(zoraV1.address, 0, 1, await finder.getAddress())
      ).eventually.rejectedWith(revert`fillNFTOffer must be active offer`);
    });

    it('should revert accepting an offer from non-token holder', async () => {
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offers
          .connect(otherUser)
          .fillNFTOffer(zoraV1.address, 0, 1, await finder.getAddress())
      ).eventually.rejectedWith(revert`fillNFTOffer must be token owner`);
    });

    it('should emit an NFTOfferFilled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );
      const events = await offers.queryFilter(
        offers.filters.NFTOfferFilled(null, null, null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('NFTOfferFilled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.buyer.toString()).to.eq(
        await deployer.getAddress()
      );
    });

    it('should emit an ExchangeExecuted event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offers
        .connect(seller)
        .createNFTOffer(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          1000,
          {
            value: ONE_ETH,
          }
        );
      await offers.fillNFTOffer(
        zoraV1.address,
        0,
        1,
        await finder.getAddress()
      );
      const events = await offers.queryFilter(
        offers.filters.ExchangeExecuted(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = offers.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ExchangeExecuted');
      expect(logDescription.args.userA).to.eq(await seller.getAddress());
      expect(logDescription.args.userB).to.eq(await deployer.getAddress());

      expect(logDescription.args.a.tokenContract).to.eq(
        ethers.constants.AddressZero
      );
      expect(logDescription.args.b.tokenContract).to.eq(zoraV1.address);
    });
  });
});
