import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  OffersV1,
  TestErc721,
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintERC721Token,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  toRoundedNumber,
  TWO_ETH,
  THREE_ETH,
  TEN_ETH,
} from '../../utils';

chai.use(asPromised);

describe('OffersV1 integration', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let weth: Weth;
  let deployer: Signer;
  let buyerA: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    buyerA = signers[1];
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

    offers = await deployOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      weth.address
    );

    await proposeModule(proposalManager, offers.address);
    await registerModule(proposalManager, offers.address);

    await approvalManager.setApprovalForModule(offers.address, true);
    await approvalManager
      .connect(buyerA)
      .setApprovalForModule(offers.address, true);
  });

  describe('Zora V1 NFT', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH offer', () => {
      async function run() {
        await offers
          .connect(buyerA)
          .createOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            { value: ONE_ETH }
          );
      }

      it('should withdraw the offer price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const afterBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw the increased offer price from the buyer', async () => {
        const initialBuyerBalance = await buyerA.getBalance();
        await run();

        await offers
          .connect(buyerA)
          .increaseOffer(1, TWO_ETH, { value: TWO_ETH });

        const postIncreasedOfferBuyerBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(postIncreasedOfferBuyerBalance)
        ).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(THREE_ETH)),
          10
        );
      });

      it('should refund the user after canceling offer', async () => {
        const initialBuyerBalance = await buyerA.getBalance();
        await run();
        const postOfferBuyerBalance = await buyerA.getBalance();
        await offers.connect(buyerA).cancelOffer(1);
        const postRefundBuyerBalance = await buyerA.getBalance();

        expect(toRoundedNumber(postOfferBuyerBalance)).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(ONE_ETH)),
          10
        );

        expect(toRoundedNumber(postRefundBuyerBalance)).to.be.approximately(
          toRoundedNumber(postOfferBuyerBalance.add(ONE_ETH)),
          10
        );
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyerA).deposit({ value: TEN_ETH });
        await weth
          .connect(buyerA)
          .approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyerA)
          .createOffer(zoraV1.address, 0, ONE_ETH, weth.address, {
            value: ONE_ETH,
          });
      }

      it('should withdraw the offer price from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw the increased offer price from the buyer', async () => {
        const initialBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await run();
        await offers
          .connect(buyerA)
          .increaseOffer(1, TWO_ETH, { value: TWO_ETH });

        const postIncreasedOfferBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        expect(
          toRoundedNumber(postIncreasedOfferBuyerBalance)
        ).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(THREE_ETH)),
          10
        );
      });

      it('should refund the user after canceling offer', async () => {
        const initialBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await run();
        const postOfferBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await offers.connect(buyerA).cancelOffer(1);
        const postRefundBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );

        expect(toRoundedNumber(postOfferBuyerBalance)).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(ONE_ETH)),
          10
        );

        expect(toRoundedNumber(postRefundBuyerBalance)).to.be.approximately(
          toRoundedNumber(postOfferBuyerBalance.add(ONE_ETH)),
          10
        );
      });
    });
  });

  describe('Vanilla NFT', () => {
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
          .connect(buyerA)
          .createOffer(
            testERC721.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            { value: ONE_ETH }
          );
      }

      it('should withdraw the offer price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const afterBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw the increased offer price from the buyer', async () => {
        const initialBuyerBalance = await buyerA.getBalance();
        await run();

        await offers
          .connect(buyerA)
          .increaseOffer(1, TWO_ETH, { value: TWO_ETH });

        const postIncreasedOfferBuyerBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(postIncreasedOfferBuyerBalance)
        ).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(THREE_ETH)),
          10
        );
      });

      it('should refund the user after canceling offer', async () => {
        const initialBuyerBalance = await buyerA.getBalance();
        await run();
        const postOfferBuyerBalance = await buyerA.getBalance();
        await offers.connect(buyerA).cancelOffer(1);
        const postRefundBuyerBalance = await buyerA.getBalance();

        expect(toRoundedNumber(postOfferBuyerBalance)).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(ONE_ETH)),
          10
        );

        expect(toRoundedNumber(postRefundBuyerBalance)).to.be.approximately(
          toRoundedNumber(postOfferBuyerBalance.add(ONE_ETH)),
          10
        );
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyerA).deposit({ value: TEN_ETH });
        await weth
          .connect(buyerA)
          .approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offers
          .connect(buyerA)
          .createOffer(testERC721.address, 0, ONE_ETH, weth.address, {
            value: ONE_ETH,
          });
      }

      it('should withdraw the offer price from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw the increased offer price from the buyer', async () => {
        const initialBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await run();
        await offers
          .connect(buyerA)
          .increaseOffer(1, TWO_ETH, { value: TWO_ETH });

        const postIncreasedOfferBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        expect(
          toRoundedNumber(postIncreasedOfferBuyerBalance)
        ).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(THREE_ETH)),
          10
        );
      });

      it('should refund the user after canceling offer', async () => {
        const initialBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await run();
        const postOfferBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );
        await offers.connect(buyerA).cancelOffer(1);
        const postRefundBuyerBalance = await weth.balanceOf(
          await buyerA.getAddress()
        );

        expect(toRoundedNumber(postOfferBuyerBalance)).to.be.approximately(
          toRoundedNumber(initialBuyerBalance.sub(ONE_ETH)),
          10
        );

        expect(toRoundedNumber(postRefundBuyerBalance)).to.be.approximately(
          toRoundedNumber(postOfferBuyerBalance.add(ONE_ETH)),
          10
        );
      });
    });
  });
});
