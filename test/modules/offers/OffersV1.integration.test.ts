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
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployTestEIP2981ERC721,
  deployTestERC271,
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const middleBalance = await buyerA.getBalance();
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyerA.getAddress());
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
      });
    });
  });

  describe('ERC-2981 NFT', () => {
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
          .connect(buyerA)
          .createOffer(
            testEIP2981ERC721.address,
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const middleBalance = await buyerA.getBalance();
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyerA.getAddress()
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
          .createOffer(testEIP2981ERC721.address, 0, ONE_ETH, weth.address, {
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyerA.getAddress());
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyerA.getAddress()
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const middleBalance = await buyerA.getBalance();
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await buyerA.getBalance();

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await testERC721.ownerOf(0)).to.eq(await buyerA.getAddress());
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

      it('should withdraw the updated offer price from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        await offers
          .connect(buyerA)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund the updated offer price to the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();

        await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund a canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyerA.getAddress());
        await offers.connect(buyerA).cancelOffer(1);
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer NFT ownership to buyer', async () => {
        await run();
        await offers.acceptOffer(1);

        expect(await testERC721.ownerOf(0)).to.eq(await buyerA.getAddress());
      });
    });
  });
});
