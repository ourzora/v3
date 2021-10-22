import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  OffersV1,
  TestEip2981Erc721,
  TestErc721,
  CollectionRoyaltyRegistryV1,
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployRoyaltyRegistry,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  toRoundedNumber,
  ONE_HALF_ETH,
  TWO_ETH,
  TEN_ETH,
  THOUSANDTH_ETH,
} from '../../utils';

chai.use(asPromised);

describe('OffersV1 integration', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let testEIP2981ERC721: TestEip2981Erc721;
  let weth: Weth;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;
  let royaltyRegistry: CollectionRoyaltyRegistryV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[2];
    finder = signers[3];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

    testERC721 = await deployTestERC271();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
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
      zoraV1.address,
      royaltyRegistry.address,
      weth.address
    );

    await proposeModule(proposalManager, offers.address);
    await registerModule(proposalManager, offers.address);

    await approvalManager.setApprovalForModule(offers.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(offers.address, true);
  });

  /**
   * NFT offers
   */

  describe('Zora V1 NFT Offer', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(zoraV1.address, 0, ONE_ETH, weth.address, 10, {
            value: ONE_ETH,
          });
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });
  });

  describe('ERC-2981 NFT Offer', () => {
    beforeEach(async () => {
      await mintERC2981Token(testEIP2981ERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testEIP2981ERC721,
        erc721TransferHelper.address,
        0
      );
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(
            testEIP2981ERC721.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyer.getAddress()
        );
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(
            testEIP2981ERC721.address,
            0,
            ONE_ETH,
            weth.address,
            10,
            {
              value: ONE_ETH,
            }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyer.getAddress()
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
        erc721TransferHelper.address,
        0
      );
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(
            testERC721.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createNFTOffer(testERC721.address, 0, ONE_ETH, weth.address, 10, {
            value: ONE_ETH,
          });
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setNFTOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setNFTOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelNFTOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillNFTOffer(1, await finder.getAddress());

        expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });
  });

  /**
   * Collection offers
   */

  describe('Zora V1 Collection Offer', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            zoraV1.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createCollectionOffer(zoraV1.address, ONE_ETH, weth.address, 10, {
            value: ONE_ETH,
          });
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(85)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });
  });

  describe('ERC-2981 Collection Offer', () => {
    beforeEach(async () => {
      await mintERC2981Token(testEIP2981ERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testEIP2981ERC721,
        erc721TransferHelper.address,
        0
      );
    });

    describe('ETH offer', () => {
      async function run() {
        await offers.connect(buyer).createCollectionOffer(
          testEIP2981ERC721.address,

          ONE_ETH,
          ethers.constants.AddressZero,
          10,
          { value: ONE_ETH }
        );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyer.getAddress()
        );
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testEIP2981ERC721.address,
            ONE_ETH,
            weth.address,
            10,
            {
              value: ONE_ETH,
            }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(50)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyer.getAddress()
        );
      });
    });
  });

  describe('Vanilla Collection Offer', () => {
    beforeEach(async () => {
      await mintERC721Token(testERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address,
        0
      );
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            ethers.constants.AddressZero,
            10,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await buyer.getBalance();

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await finder.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await deployer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyer)
          .createCollectionOffer(
            testERC721.address,
            ONE_ETH,
            weth.address,
            10,
            {
              value: ONE_ETH,
            }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offers
          .connect(buyer)
          .setCollectionOfferPrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offers.connect(buyer).setCollectionOfferPrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offers.connect(buyer).cancelCollectionOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

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
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(100))),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(
            beforeBalance.add(ONE_ETH.sub(THOUSANDTH_ETH.mul(100)))
          ),
          10
        );
      });

      it('should transfer NFT to buyer after accepted offer', async () => {
        await run();
        await offers.fillCollectionOffer(1, 0, await finder.getAddress());

        expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
      });
    });
  });
});
