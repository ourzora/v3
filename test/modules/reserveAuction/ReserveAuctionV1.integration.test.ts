import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import { Market, Media } from '@zoralabs/core/dist/typechain';
import {
  BadERC721,
  ReserveAuctionV1,
  TestEIP2981ERC721,
  TestERC721,
  WETH,
  ERC20TransferHelper,
  ERC721TransferHelper,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployBadERC721,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployReserveAuctionV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_DAY,
  ONE_ETH,
  ONE_HALF_ETH,
  proposeModule,
  registerModule,
  TENTH_ETH,
  THOUSANDTH_ETH,
  timeTravelToEndOfAuction,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('ReserveAuctionV1 integration', () => {
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let zoraV1Market: Market;
  let badERC721: BadERC721;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let listingFeeRecipient: Signer;
  let bidderA: Signer;
  let bidderB: Signer;
  let sellerFundsRecipient: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    const signers = await ethers.getSigners();
    deployer = signers[0];
    listingFeeRecipient = signers[1];
    bidderA = signers[2];
    bidderB = signers[3];
    sellerFundsRecipient = signers[4];
    otherUser = signers[5];
    finder = signers[5];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    zoraV1Market = zoraProtocol.market;
    badERC721 = await deployBadERC721();
    testERC721 = await deployTestERC271();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
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
    reserveAuction = await deployReserveAuctionV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      zoraV1Market.address,
      royaltyEngine.address,
      weth.address
    );
    await proposeModule(proposalManager, reserveAuction.address);
    await registerModule(proposalManager, reserveAuction.address);

    await approvalManager.setApprovalForModule(reserveAuction.address, true);
    await approvalManager
      .connect(deployer)
      .setApprovalForModule(reserveAuction.address, true);
    await approvalManager
      .connect(bidderA)
      .setApprovalForModule(reserveAuction.address, true);
    await approvalManager
      .connect(bidderB)
      .setApprovalForModule(reserveAuction.address, true);
    await approvalManager
      .connect(otherUser)
      .setApprovalForModule(reserveAuction.address, true);
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

    describe('ETH auction', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress(), {
            value: ONE_HALF_ETH,
          });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await zoraV1.ownerOf(0)).to.eq(await bidderB.getAddress());
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await bidderB.getBalance();
        await run();
        const afterBalance = await bidderB.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 10);
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await bidderA.getBalance();
        await run();
        const afterBalance = await bidderA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(0, 10);
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await sellerFundsRecipient.getBalance();
        await run();
        const afterBalance = await sellerFundsRecipient.getBalance();

        // 15% creator fee + 10% listing fee + 10% finders fee
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(680))),
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

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });
    });

    describe('WETH auction', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
        await weth.connect(bidderB).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await zoraV1.ownerOf(0)).to.eq(await bidderB.getAddress());
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderB.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderB.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(0);
      });

      it('should pay the funds recipient', async () => {
        const beforeBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await sellerFundsRecipient.getAddress()
        );

        // 15% creator fee + 10% listing fee + 10% finders fee -> 1 WETH * 15% * 20%  = .68WETH
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

        // 15% creator fee -> 0.85 ETH * 10% listing fee -> 0.085 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(85))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 15% creator fee -> 0.85 ETH * 10% finder fee -> 0.085 ETH
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
        0
      );
    });

    describe('ETH auction', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress(), {
            value: ONE_HALF_ETH,
          });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await bidderB.getAddress()
        );
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await bidderB.getBalance();
        await run();
        const afterBalance = await bidderB.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await bidderA.getBalance();
        await run();
        const afterBalance = await bidderA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(0, 10);
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

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
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

    describe('WETH auction', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
        await weth.connect(bidderB).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
          await bidderB.getAddress()
        );
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderB.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderB.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(0);
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

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(50))),
          10
        );
      });

      it('should pay the royalty recipient', async () => {
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

  describe('Vanilla NFT', () => {
    beforeEach(async () => {
      await mintERC721Token(testERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address,
        0
      );
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [0]
      );
    });

    describe('ETH auction', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress(), {
            value: ONE_HALF_ETH,
          });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await testERC721.ownerOf(0)).to.eq(await bidderB.getAddress());
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await bidderB.getBalance();
        await run();
        const afterBalance = await bidderB.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await bidderA.getBalance();
        await run();
        const afterBalance = await bidderA.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(0, 10);
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

        // 10% listing fee -> 0.9 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await finder.getBalance();
        await run();
        const afterBalance = await finder.getBalance();

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });
    });

    describe('WETH auction', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
        await weth.connect(bidderB).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, ONE_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await listingFeeRecipient.getAddress(),
            await sellerFundsRecipient.getAddress(),
            10,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_HALF_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await timeTravelToEndOfAuction(reserveAuction, 1, true);
        await reserveAuction.connect(otherUser).settleAuction(1);
      }

      it('should transfer the NFT to the winning bidder', async () => {
        await run();
        expect(await testERC721.ownerOf(0)).to.eq(await bidderB.getAddress());
      });

      it('should withdraw the winning bid amount from the winning bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderB.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderB.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(
          toRoundedNumber(ONE_ETH)
        );
      });

      it('should refund the losing bidder', async () => {
        const beforeBalance = await weth.balanceOf(await bidderA.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await bidderA.getAddress());

        expect(toRoundedNumber(beforeBalance.sub(afterBalance))).to.eq(0);
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

        // 10% listing fee -> 0.9 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });

      it('should pay the finder', async () => {
        const beforeBalance = await weth.balanceOf(await finder.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await finder.getAddress());

        // 50% creator fee -> 0.5 ETH * 10% listing fee -> 0.05 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH)),
          10
        );
      });
    });
  });
});
