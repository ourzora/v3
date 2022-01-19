import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';

import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  AsksV1,
  TestEIP2981ERC721,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployAsksV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC721,
  deployWETH,
  deployZoraModuleManager,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_ETH,
  registerModule,
  TENTH_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  deployZoraProtocol,
  deployProtocolFeeSettings,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('AsksV1 integration', () => {
  let asks: AsksV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyerA: Signer;
  let sellerFundsRecipient: Signer;
  let listingFeeRecipient: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    sellerFundsRecipient = signers[2];
    finder = signers[4];
    listingFeeRecipient = signers[5];
    testERC721 = await deployTestERC721();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    royaltyEngine = await deployRoyaltyEngine();
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
    asks = await deployAsksV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );
    await registerModule(moduleManager, asks.address);

    await moduleManager.setApprovalForModule(asks.address, true);
    await moduleManager
      .connect(buyerA)
      .setApprovalForModule(asks.address, true);
  });

  describe('Zora V1 NFT', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH ask', () => {
      async function run() {
        await asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(zoraV1.address, 0, await finder.getAddress(), {
            value: ONE_ETH,
          });
      }

      it('should transfer the NFT to the buyer', async () => {
        await run();

        expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
      });

      it('should withdraw the ask price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const afterBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 1 ETH * 15% creator fee -> ***0.15 ETH creator*** -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(150))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> ***0.085 ETH lister*** -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> ***0.0765 ETH finder*** --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(76))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> ***0.6885 ETH seller***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(688))),
          10
        );
      });
    });

    describe('WETH ask', () => {
      beforeEach(async () => {
        await weth.connect(buyerA).deposit({ value: ONE_ETH });
        await weth
          .connect(buyerA)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          weth.address,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(zoraV1.address, 0, await finder.getAddress());
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
      });

      it('should withdraw the ask price amount from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 1 ETH * 15% creator fee -> ***0.15 ETH creator*** -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(150)))
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );
        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> ***0.085 ETH lister*** -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          1000
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> ***0.0765 ETH finder*** --> 0.6885 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(76))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 1 ETH * 15% creator fee -> 0.15 ETH creator -> 0.85 ETH remaining
        // 0.85 ETH * 1000 bps listing fee -> 0.085 ETH lister -> 0.765 ETH remaining
        // 0.765 ETH * 1000 bps finders fee -> 0.0765 ETH finder --> ***0.6885 ETH seller***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(688))),
          10
        );
      });
    });
  });

  describe('ERC-2981 NFT', () => {
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

    describe('ETH ask', () => {
      async function run() {
        await asks.createAsk(
          testEIP2981ERC721.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(testEIP2981ERC721.address, 0, await finder.getAddress(), {
            value: ONE_ETH,
          });
      }

      it('should transfer the NFT to the buyer', async () => {
        await run();

        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyerA.getAddress()
        );
      });

      it('should withdraw the ask price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const afterBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should pay the royalty recipient', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 1 ETH * 50% creator fee -> ***0.5 ETH creator*** -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(5))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> ***0.05 ETH lister*** -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> ***0.045 ETH finder*** --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(45))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> ***0.405 ETH seller***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(405))),
          10
        );
      });
    });

    describe('WETH ask', () => {
      beforeEach(async () => {
        await weth.connect(buyerA).deposit({ value: ONE_ETH });
        await weth
          .connect(buyerA)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await asks.createAsk(
          testEIP2981ERC721.address,
          0,
          ONE_ETH,
          weth.address,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(testEIP2981ERC721.address, 0, await finder.getAddress());
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await buyerA.getAddress()
        );
      });

      it('should withdraw the ask price amount from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should pay the royalty recipient', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 1 ETH * 50% creator fee -> ***0.5 ETH creator*** -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(5))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> ***0.05 ETH lister*** -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> ***0.045 ETH finder*** --> 0.405 ETH seller
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(45))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 1 ETH * 50% creator fee -> 0.5 ETH creator -> 0.5 ETH remaining
        // 0.5 ETH * 1000 bps listing fee -> 0.05 ETH lister -> 0.45 ETH remaining
        // 0.45 ETH * 1000 bps finders fee -> 0.045 ETH finder --> ***0.405 ETH seller***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(405))),
          10
        );
      });
    });
  });

  describe('Vanilla NFT', async () => {
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

    describe('ETH ask', () => {
      async function run() {
        await asks.createAsk(
          testERC721.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(testERC721.address, 0, await finder.getAddress(), {
            value: ONE_ETH,
          });
      }

      it('should transfer the NFT to the buyer', async () => {
        await run();

        expect(await testERC721.ownerOf(0)).to.eq(await buyerA.getAddress());
      });

      it('should withdraw the ask price from the buyer', async () => {
        const beforeBalance = await buyerA.getBalance();
        await run();
        const afterBalance = await buyerA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 1 ETH * 1000 bps listing fee -> ***0.1 ETH lister*** -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> 0.09 ETH finder --> 0.81 ETH remaining
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 1000 bps listing fee -> 0.1 ETH lister -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> ***0.09 ETH finder*** --> 0.81 ETH remaining
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(90))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 1 ETH * 1000 bps listing fee -> 0.1 ETH lister -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> 0.09 ETH finder --> ***0.81 ETH remaining***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(810))),
          10
        );
      });
    });

    describe('WETH ask', () => {
      beforeEach(async () => {
        await weth.connect(buyerA).deposit({ value: ONE_ETH });
        await weth
          .connect(buyerA)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await asks.createAsk(
          testERC721.address,
          0,
          ONE_ETH,
          weth.address,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          1000,
          1000
        );

        await asks
          .connect(buyerA)
          .fillAsk(testERC721.address, 0, await finder.getAddress());
      }

      it('should transfer the NFT to the buyer', async () => {
        await run();

        expect(await testERC721.ownerOf(0)).to.eq(await buyerA.getAddress());
      });

      it('should withdraw the ask price amount from the buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyerA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyerA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await listingFeeRecipient.getAddress()
        );

        // 1 ETH * 1000 bps listing fee -> ***0.1 ETH lister*** -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> 0.09 ETH finder --> 0.81 ETH remaining
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 ETH * 1000 bps listing fee -> 0.1 ETH lister -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> ***0.09 ETH finder*** --> 0.81 ETH remaining
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(90))),
          10
        );
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 1 ETH * 1000 bps listing fee -> 0.1 ETH lister -> 0.9 ETH remaining
        // 0.9 ETH * 1000 bps finders fee -> 0.09 ETH finder --> ***0.81 ETH remaining***
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(810))),
          10
        );
      });
    });
  });
});
