import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import {
  approveNFTTransfer,
  deployBadERC721,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployReserveAuctionV1,
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
  proposeModule,
  registerModule,
  TENTH_ETH,
  THOUSANDTH_ETH,
  timeTravelToEndOfAuction,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
import { Media } from '@zoralabs/core/dist/typechain';
import { Signer } from 'ethers';
import {
  BadErc721,
  ReserveAuctionV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
  Erc20TransferHelper,
  Erc721TransferHelper,
} from '../../../typechain';

chai.use(asPromised);

describe('ReserveAuctionV1 integration', () => {
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let badERC721: BadErc721;
  let testERC721: TestErc721;
  let testEIP2981ERC721: TestEip2981Erc721;
  let weth: Weth;
  let deployer: Signer;
  let host: Signer;
  let bidderA: Signer;
  let bidderB: Signer;
  let fundsRecipient: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    const signers = await ethers.getSigners();
    deployer = signers[0];
    host = signers[1];
    bidderA = signers[2];
    bidderB = signers[3];
    fundsRecipient = signers[4];
    otherUser = signers[5];
    finder = signers[5];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    badERC721 = await deployBadERC721();
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
    reserveAuction = await deployReserveAuctionV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
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
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH auction with no host', async () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 15% creator fee -> 2ETH * 85% = 1.7 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(1530))),
          10
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 15% creator fee -> 2ETH * 15% = 0.3 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(3))),
          10
        );
      });
    });

    describe('ETH auction with host', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 15% creator fee -> 2ETH * 85% = 1.7 ETH
        // 20% host fee -> 1.7 ETH * 80% = 1.36 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(1190))),
          10
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 15% creator fee -> 2ETH * 15% = 0.3 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(3))),
          10
        );
      });
    });

    describe('WETH auction with no host', () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 15% creator fee -> 2ETH * 85% = 1.7 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(1530)))
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 15% creator fee -> 2ETH * 15% = 0.3 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(3)))
        );
      });
    });

    describe('WETH auction with host', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            zoraV1.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 15% creator fee -> 2ETH * 85% = 1.7 WETH
        // 20% host fee -> 1.7 ETH * 80% = 1.36 ETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(1190)))
        );
      });

      it('should pay the token creator', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 15% creator fee -> 2ETH * 15% = 0.3 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(3)))
        );
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

    describe('ETH auction with no host', async () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 50% creator fee -> 2ETH * 50% = 1 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(9))),
          10
        );
      });

      it('should pay the royaltyRecipient', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 50% creator fee -> 2ETH * 50% = 1 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(ONE_ETH)),
          10
        );
      });
    });

    describe('ETH auction with host', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 50% creator fee -> 2ETH * 50% = 1 ETH
        // 20% host fee -> 1 ETH * 80% = 0.8 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(7))),
          10
        );
      });

      it('should pay the royaltyRecipient', async () => {
        const beforeBalance = await deployer.getBalance();
        await run();
        const afterBalance = await deployer.getBalance();

        // 50% creator fee -> 2ETH * 50% = 1 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(ONE_ETH)),
          10
        );
      });
    });

    describe('WETH auction with no host', () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 50% creator fee -> 2ETH * 50% = 1 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(9)))
        );
      });

      it('should pay the royaltyRecipient', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 50% creator fee -> 2ETH * 50% = 1 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(ONE_ETH))
        );
      });
    });

    describe('WETH auction with host', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testEIP2981ERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 50% creator fee -> 2ETH * 50% = 1 WETH
        // 20% host fee -> 1 ETH * 80% = 0.8 ETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(7)))
        );
      });

      it('should pay the royalty recipient', async () => {
        const beforeBalance = await weth.balanceOf(await deployer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await deployer.getAddress());

        // 50% creator fee -> 1ETH * 50% = 1 WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(ONE_ETH))
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

    describe('ETH auction with no host', async () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(18))),
          10
        );
      });
    });

    describe('ETH auction with host', () => {
      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            ethers.constants.AddressZero
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress(), { value: TWO_ETH });
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
        ).to.be.approximately(toRoundedNumber(TWO_ETH), 10);
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 20% host fee -> 2 ETH * 80% = 1.6 ETH
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(14))),
          10
        );
      });
    });

    describe('WETH auction with no host', () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            ethers.constants.AddressZero,
            await fundsRecipient.getAddress(),
            0,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(18)))
        );
      });
    });

    describe('WETH auction with host', async () => {
      beforeEach(async () => {
        await weth.connect(bidderA).deposit({ value: ONE_ETH });
        await weth
          .connect(bidderA)
          .approve(erc20TransferHelper.address, ONE_ETH);
        await weth.connect(bidderB).deposit({ value: TWO_ETH });
        await weth
          .connect(bidderB)
          .approve(erc20TransferHelper.address, TWO_ETH);
      });

      async function run() {
        await reserveAuction
          .connect(deployer)
          .createAuction(
            0,
            testERC721.address,
            ONE_DAY,
            TENTH_ETH,
            await host.getAddress(),
            await fundsRecipient.getAddress(),
            20,
            10,
            weth.address
          );

        await reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH, await finder.getAddress());
        await reserveAuction
          .connect(bidderB)
          .createBid(1, TWO_ETH, await finder.getAddress());
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
          toRoundedNumber(TWO_ETH)
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 20% host fee -> 2 ETH * 80% = 1.6 ETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(TENTH_ETH.mul(14)))
        );
      });
    });
  });
});
