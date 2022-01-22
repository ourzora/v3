import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CollectionOffersV1,
  TestEIP2981ERC721,
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
  deployTestEIP2981ERC721,
  deployTestERC721,
  deployWETH,
  deployZoraModuleManager,
  deployZoraProtocol,
  mintZoraNFT,
  mintERC2981Token,
  mintERC721Token,
  ONE_ETH,
  ONE_HALF_ETH,
  registerModule,
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  THREE_ETH,
  toRoundedNumber,
  TWO_ETH,
  TEN_ETH,
  deployProtocolFeeSettings,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('CollectionOffersV1 integration', () => {
  let collectionOffers: CollectionOffersV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let finder: Signer;
  let seller: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    finder = signers[1];
    seller = signers[2];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

    testERC721 = await deployTestERC721();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    weth = await deployWETH();

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

    collectionOffers = await deployCollectionOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );

    await registerModule(moduleManager, collectionOffers.address);

    await moduleManager.setApprovalForModule(collectionOffers.address, true);
    await moduleManager
      .connect(seller)
      .setApprovalForModule(collectionOffers.address, true);
  });

  describe('ZORA V1 Collection Offer', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    async function run() {
      await collectionOffers
        .connect(seller)
        .createCollectionOffer(zoraV1.address, {
          value: ONE_ETH,
        });
    }

    it('should withdraw offer amount from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const afterBalance = await seller.getBalance();

      expect(
        toRoundedNumber(beforeBalance.sub(afterBalance))
      ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
    });

    it('should withdraw offer increase amount from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(zoraV1.address, 1, TWO_ETH, {
          value: ONE_ETH,
        });

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(TWO_ETH)),
        10
      );
    });

    it('should refund offer decrease to seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(zoraV1.address, 1, ONE_HALF_ETH);

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
        10
      );
    });

    it('should refund canceled offer', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const middleBalance = await seller.getBalance();
      await collectionOffers
        .connect(seller)
        .cancelCollectionOffer(zoraV1.address, 1);
      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(middleBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_ETH)),
        10
      );
      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(middleBalance.add(ONE_ETH)),
        10
      );
    });

    it('should pay the finder', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(10))),
        10
      );
    });

    it('should pay the finder an updated finders fee', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers
        .connect(seller)
        .setCollectionOfferFindersFee(zoraV1.address, 1, 1000);
      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
        100
      );
    });

    it('should transfer funds from accepted offer to seller', async () => {
      const beforeBalance = await deployer.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await deployer.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(10)))),
        10
      );
    });

    it('should transfer NFT to seller after accepted offer', async () => {
      await run();
      await collectionOffers.fillCollectionOffer(
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
    });
  });

  describe('ERC-2981 Collection Offer', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [ONE_ETH.div(2)]
      );
      await mintERC2981Token(testEIP2981ERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testEIP2981ERC721,
        erc721TransferHelper.address
      );
    });

    async function run() {
      await collectionOffers
        .connect(seller)
        .createCollectionOffer(testEIP2981ERC721.address, { value: ONE_ETH });
    }

    it('should withdraw offer from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const afterBalance = await seller.getBalance();

      expect(
        toRoundedNumber(beforeBalance.sub(afterBalance))
      ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
    });

    it('should withdraw offer increase from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(testEIP2981ERC721.address, 1, TWO_ETH, {
          value: ONE_ETH,
        });

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(TWO_ETH)),
        10
      );
    });

    it('should refund offer decrease to seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(testEIP2981ERC721.address, 1, ONE_HALF_ETH);

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
        10
      );
    });

    it('should refund canceled offer', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const middleBalance = await seller.getBalance();
      await collectionOffers
        .connect(seller)
        .cancelCollectionOffer(testEIP2981ERC721.address, 1);
      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(middleBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_ETH)),
        10
      );
      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(middleBalance.add(ONE_ETH)),
        10
      );
    });

    it('should pay the finder', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        testEIP2981ERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(10))),
        10
      );
    });

    it('should pay the finder an updated finders fee', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers
        .connect(seller)
        .setCollectionOfferFindersFee(testEIP2981ERC721.address, 1, 1000);
      await collectionOffers.fillCollectionOffer(
        testEIP2981ERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
        100
      );
    });

    it('should transfer funds from accepted offer to seller', async () => {
      const beforeBalance = await deployer.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        testEIP2981ERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await deployer.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(10)))),
        10
      );
    });

    it('should transfer NFT to seller after accepted offer', async () => {
      await run();
      await collectionOffers.fillCollectionOffer(
        testEIP2981ERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
        await seller.getAddress()
      );
    });
  });

  describe('Vanilla ERC-721 Collection Offer', () => {
    beforeEach(async () => {
      await mintERC721Token(testERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address
      );
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [0]
      );
    });

    async function run() {
      await collectionOffers
        .connect(seller)
        .createCollectionOffer(testERC721.address, { value: ONE_ETH });
    }

    it('should withdraw offer from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const afterBalance = await seller.getBalance();

      expect(
        toRoundedNumber(beforeBalance.sub(afterBalance))
      ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
    });

    it('should withdraw offer increase from seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(testERC721.address, 1, TWO_ETH, {
          value: ONE_ETH,
        });

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(TWO_ETH)),
        10
      );
    });

    it('should refund offer decrease to seller', async () => {
      const beforeBalance = await seller.getBalance();
      await run();

      await collectionOffers
        .connect(seller)
        .setCollectionOfferAmount(testERC721.address, 1, ONE_HALF_ETH);

      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
        10
      );
    });

    it('should refund canceled offer', async () => {
      const beforeBalance = await seller.getBalance();
      await run();
      const middleBalance = await seller.getBalance();
      await collectionOffers
        .connect(seller)
        .cancelCollectionOffer(testERC721.address, 1);
      const afterBalance = await seller.getBalance();

      expect(toRoundedNumber(middleBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.sub(ONE_ETH)),
        10
      );
      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(middleBalance.add(ONE_ETH)),
        10
      );
    });

    it('should pay the finder', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        testERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(10))),
        10
      );
    });

    it('should pay the finder an updated finders fee', async () => {
      const beforeBalance = await finder.getBalance();
      await run();
      await collectionOffers
        .connect(seller)
        .setCollectionOfferFindersFee(testERC721.address, 1, 1000);
      await collectionOffers.fillCollectionOffer(
        testERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await finder.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
        100
      );
    });

    it('should transfer funds from accepted offer to seller', async () => {
      const beforeBalance = await deployer.getBalance();
      await run();
      await collectionOffers.fillCollectionOffer(
        testERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const afterBalance = await deployer.getBalance();

      expect(toRoundedNumber(afterBalance)).to.be.approximately(
        toRoundedNumber(beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(10)))),
        10
      );
    });

    it('should transfer NFT to seller after accepted offer', async () => {
      await run();
      await collectionOffers.fillCollectionOffer(
        testERC721.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      expect(await testERC721.ownerOf(0)).to.eq(await seller.getAddress());
    });
  });
});
