import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  OffersV1,
  TestEIP2981ERC721,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC721,
  deployWETH,
  deployZoraModuleManager,
  deployZoraProtocol,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_ETH,
  registerModule,
  toRoundedNumber,
  ONE_HALF_ETH,
  TWO_ETH,
  TEN_ETH,
  THOUSANDTH_ETH,
  deployProtocolFeeSettings,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('OffersV1 integration', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let seller: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    seller = signers[1];
    otherUser = signers[2];
    finder = signers[3];

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
  });

  /**
   * NFT offers
   */

  describe('Zora V1 NFT Offer', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            1000,
            { value: ONE_ETH }
          );
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

        await offers
          .connect(seller)
          .setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await seller.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to seller', async () => {
        const beforeBalance = await seller.getBalance();
        await run();

        await offers
          .connect(seller)
          .setNFTOfferAmount(zoraV1.address, 0, 1, ONE_HALF_ETH);

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
        await offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1);
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
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(seller).deposit({ value: TEN_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(zoraV1.address, 0, ONE_ETH, weth.address, 1000, {
            value: ONE_ETH,
          });
      }

      it('should withdraw offer from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        await offers
          .connect(seller)
          .setNFTOfferAmount(zoraV1.address, 0, 1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await seller.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();

        await offers
          .connect(seller)
          .setNFTOfferAmount(zoraV1.address, 0, 1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await seller.getAddress());
        await offers.connect(seller).cancelNFTOffer(zoraV1.address, 0, 1);
        const afterBalance = await weth.balanceOf(await seller.getAddress());

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
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          zoraV1.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
      });
    });
  });

  describe('ERC-2981 NFT Offer', () => {
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

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(
            testEIP2981ERC721.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            1000,
            { value: ONE_ETH }
          );
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

        await offers
          .connect(seller)
          .setNFTOfferAmount(testEIP2981ERC721.address, 0, 1, TWO_ETH, {
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

        await offers
          .connect(seller)
          .setNFTOfferAmount(testEIP2981ERC721.address, 0, 1, ONE_HALF_ETH);

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
        await offers
          .connect(seller)
          .cancelNFTOffer(testEIP2981ERC721.address, 0, 1);
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
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await seller.getAddress()
        );
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(seller).deposit({ value: TEN_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(
            testEIP2981ERC721.address,
            0,
            ONE_ETH,
            weth.address,
            1000,
            {
              value: ONE_ETH,
            }
          );
      }

      it('should withdraw offer from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        await offers
          .connect(seller)
          .setNFTOfferAmount(testEIP2981ERC721.address, 0, 1, TWO_ETH, {
            value: ONE_ETH,
          });

        const afterBalance = await weth.balanceOf(await seller.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();

        await offers
          .connect(seller)
          .setNFTOfferAmount(testEIP2981ERC721.address, 0, 1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await seller.getAddress());
        await offers
          .connect(seller)
          .cancelNFTOffer(testEIP2981ERC721.address, 0, 1);
        const afterBalance = await weth.balanceOf(await seller.getAddress());

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
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          testEIP2981ERC721.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await seller.getAddress()
        );
      });
    });
  });

  describe('Vanilla NFT Offer', () => {
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

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(
            testERC721.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            1000,
            { value: ONE_ETH }
          );
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

        await offers
          .connect(seller)
          .setNFTOfferAmount(testERC721.address, 0, 1, TWO_ETH, {
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

        await offers
          .connect(seller)
          .setNFTOfferAmount(testERC721.address, 0, 1, ONE_HALF_ETH);

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
        await offers.connect(seller).cancelNFTOffer(testERC721.address, 0, 1);
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
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await testERC721.ownerOf(0)).to.eq(await seller.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(seller).deposit({ value: TEN_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(seller)
          .createNFTOffer(testERC721.address, 0, ONE_ETH, weth.address, 1000, {
            value: ONE_ETH,
          });
      }

      it('should withdraw offer from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        await offers
          .connect(seller)
          .setNFTOfferAmount(testERC721.address, 0, 1, TWO_ETH, {
            value: ONE_ETH,
          });

        const afterBalance = await weth.balanceOf(await seller.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to seller', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();

        await offers
          .connect(seller)
          .setNFTOfferAmount(testERC721.address, 0, 1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await seller.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await seller.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await seller.getAddress());
        await offers.connect(seller).cancelNFTOffer(testERC721.address, 0, 1);
        const afterBalance = await weth.balanceOf(await seller.getAddress());

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
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to seller after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(
          testERC721.address,
          0,
          1,
          await finder.getAddress()
        );

        expect(await testERC721.ownerOf(0)).to.eq(await seller.getAddress());
      });
    });
  });
});
