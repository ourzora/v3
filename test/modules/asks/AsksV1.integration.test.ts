import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';

import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  AsksV1,
  CollectionRoyaltyRegistryV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployAsksV1,
  deployRoyaltyRegistry,
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
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
chai.use(asPromised);

describe('AsksV1 integration', () => {
  let asks: AsksV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let testEIP2981ERC721: TestEip2981Erc721;
  let weth: Weth;
  let deployer: Signer;
  let buyerA: Signer;
  let fundsRecipient: Signer;
  let listingFeeRecipient: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;
  let royaltyRegistry: CollectionRoyaltyRegistryV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    fundsRecipient = signers[2];
    listingFeeRecipient = signers[3];
    otherUser = signers[4];
    finder = signers[5];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    testERC721 = await deployTestERC271();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    royaltyRegistry = await deployRoyaltyRegistry();
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
      zoraV1.address,
      royaltyRegistry.address,
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
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks
          .connect(buyerA)
          .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

        // 15% creator fee + 10% ask fee + 10% finders fee
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(680))),
          10
        );
      });

      it('should pay the ask fee recipient', async () => {
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
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks.connect(buyerA).fillAsk(1, await finder.getAddress());
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
        );

        // 15% creator fee + 10% listingFeeRecipient fee + 10% finders fee -> 1 WETH * 15% * 20%  = .68WETH
        expect(toRoundedNumber(afterBalance)).to.eq(
          toRoundedNumber(beforeBalance.add(THOUSANDTH_ETH.mul(680)))
        );
      });

      it('should pay the ask fee recipient', async () => {
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
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks
          .connect(buyerA)
          .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

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
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks.connect(buyerA).fillAsk(1, await finder.getAddress());
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
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
    });

    describe('ETH ask', () => {
      async function run() {
        await asks.createAsk(
          testERC721.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks
          .connect(buyerA)
          .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });
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
        const beforeBalance = await fundsRecipient.getBalance();
        await run();
        const afterBalance = await fundsRecipient.getBalance();

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
          await fundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          10,
          10
        );

        await asks.connect(buyerA).fillAsk(1, await finder.getAddress());
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
          await fundsRecipient.getAddress()
        );
        await run();
        const afterBalance = await weth.balanceOf(
          await fundsRecipient.getAddress()
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
