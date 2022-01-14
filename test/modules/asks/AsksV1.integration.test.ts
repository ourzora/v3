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

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 15% creator fee -> 0.85 ETH * 1000 bps finders fee -> 0.085 ETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 1 ETH * 15% creator fee -> 0.15 ETH creator
        // 0.85 ETH * 1000 bps finders fee -> 0.765 ETH remaining
        // 0.15 ETH + 0.765 ETH -> 0.915 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(915))),
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
        await asks.createAsk(zoraV1.address, 0, ONE_ETH, weth.address, 1000);

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

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 WETH * 15% creator fee -> 0.85 WETH * 1000 bps finders fee -> 0.085 WETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          1000
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 1 WETH * 15% creator fee -> 0.15 WETH creator
        // 0.85 WETH * 1000 bps finders fee -> 0.765 WETH remaining
        // 0.15 WETH + 0.765 WETH -> 0.915 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(915)))
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

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 50% creator fee -> 0.5 ETH * 1000 bps finders fee -> 0.05 ETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the royalty recipient', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 1 ETH * 50% creator fee -> 0.5 ETH royalty recipient
        // 0.5 ETH * 1000 bps finders fee -> 0.45 ETH remaining
        // 0.5 ETH + 0.45 ETH -> 0.95 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(950))),
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

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 WETH * 50% creator fee -> 0.5 WETH * 1000 bps finders fee -> 0.05 WETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the royaltyRecipient', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 1 WETH * 50% creator fee -> 0.5 WETH royalty recipient
        // 0.5 WETH * 1000 bps finders fee -> 0.45 WETH remaining
        // 0.5 WETH + 0.45 WETH -> 0.95 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(950)))
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

      it('should pay the seller', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 1 ETH * 1000 bps finders fee -> 0.9 ETH funds recipient
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(9))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 1 ETH * 1000 bps finders fee -> 0.1 ETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
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

      it('should pay the seller', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 1 WETH * 1000 bps finders fee -> 0.9 WETH funds recipient
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(9))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 1 WETH * 1000 bps finders fee -> 0.1 WETH finder
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });
    });
  });
});
