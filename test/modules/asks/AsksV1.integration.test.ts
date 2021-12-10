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
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  TENTH_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  deployZoraProtocol,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe.only('AsksV1 integration', () => {
  let asks: AsksV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyerA: Signer;
  let sellerFundsRecipient: Signer;
  let listingFeeRecipient: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    sellerFundsRecipient = signers[2];
    listingFeeRecipient = signers[3];
    otherUser = signers[4];
    finder = signers[5];
    testERC721 = await deployTestERC271();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    royaltyEngine = await deployRoyaltyEngine();
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
    asks = await deployAsksV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      weth.address
    );

    await proposeModule(proposalManager, asks.address);
    await registerModule(proposalManager, asks.address);

    await approvalManager.setApprovalForModule(asks.address, true);
    await approvalManager
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
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 15% creator fee + 10% ask fee + 10% finders fee
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(680))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 15% creator fee -> 0.85 ETH * 10% ask fee -> 0.085 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 15% creator fee -> 1ETH * 15% = 0.15 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(150))),
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
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 15% creator fee + 10% listingFeeRecipient fee + 10% finders fee -> 1 WETH * 15% * 20%  = .68WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(680)))
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

        // 15% creator fee -> 0.85 ETH * 10% ask fee -> 0.085 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 15% creator fee -> 1 WETH * 15% = .15WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(150)))
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
        erc721TransferHelper.address,
        '0'
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
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 50% creator fee -> 1ETH * 50% = 0.5 ETH * 20% fees -> .4 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(4))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the royalty recipient', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 50% creator fee -> 1ETH * 50% = 0.5 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(5))),
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
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 50% creator fee -> 1ETH * 50% = 0.5 ETH * 20% fees -> .4 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(4))),
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

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the royaltyRecipient', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 50% creator fee -> 1 WETH * 50% = .5WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(5)))
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
        erc721TransferHelper.address,
        '0'
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
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 20% fees -> 0.8 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(8))),
          10
        );
      });

      it('should pay the listing fee recipient', async () => {
        const beforeBalance = await listingFeeRecipient.getBalance();
        await run();
        const afterBalance = await listingFeeRecipient.getBalance();

        // 10% ask fee -> 0.9 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
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
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
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

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 20% fees -> 0.8 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(8))),
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

        // 10% ask fee -> 0.9 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 50% creator fee -> 0.5 ETH * 10% ask fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });
    });
  });
});
