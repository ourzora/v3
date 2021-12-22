import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';

import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredCallsV1,
  TestEIP2981ERC721,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCoveredCallsV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
  ONE_HALF_ETH,
  ONE_ETH,
  proposeModule,
  registerModule,
  TWO_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  deployZoraProtocol,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('CoveredCallsV1 integration', () => {
  let calls: CoveredCallsV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyer: Signer;
  let sellerFundsRecipient: Signer;
  let otherUser: Signer;
  let operator: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    sellerFundsRecipient = signers[2];
    otherUser = signers[3];
    operator = signers[4];

    const zoraV1Protocol = await deployZoraProtocol();
    zoraV1 = zoraV1Protocol.media;
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
    royaltyEngine = await deployRoyaltyEngine();
    calls = await deployCoveredCallsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      weth.address
    );

    await proposeModule(proposalManager, calls.address);
    await registerModule(proposalManager, calls.address);

    await approvalManager.setApprovalForModule(calls.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(calls.address, true);
  });

  describe('ZORA v1 NFT', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH', () => {
      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );

          await calls
            .connect(buyer)
            .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });
        }

        it('should transfer NFT to contract', async () => {
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await buyer.getBalance();
          await run();
          const afterBalance = await buyer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );

          await calls
            .connect(buyer)
            .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

          await calls
            .connect(buyer)
            .exerciseCall(zoraV1.address, 0, { value: ONE_ETH });
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          // 0.5ETH premium + 0.85ETH strike (1ETH * 15% creator fee)
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(
            toRoundedNumber(ethers.utils.parseEther('1.35')),
            5
          );
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TWO_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TWO_ETH);
      });

      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(zoraV1.address, 0);
        }

        it('should transfer NFT to contract', async () => {
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(await buyer.getAddress());
          await run();
          const afterBalance = await weth.balanceOf(await buyer.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(zoraV1.address, 0);
          await calls.connect(buyer).exerciseCall(zoraV1.address, 0);
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          // 0.5ETH premium + 0.85ETH strike (1ETH * 15% creator fee)
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(
            toRoundedNumber(ethers.utils.parseEther('1.35')),
            5
          );
        });
      });
    });
  });

  describe('EIP2981 NFT', () => {
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

    describe('ETH', () => {
      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );

          await calls
            .connect(buyer)
            .buyCall(testEIP2981ERC721.address, 0, { value: ONE_HALF_ETH });
        }
        it('should transfer NFT to contract', async () => {
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await buyer.getBalance();
          await run();
          const afterBalance = await buyer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );
          await calls
            .connect(buyer)
            .buyCall(testEIP2981ERC721.address, 0, { value: ONE_HALF_ETH });
          await calls
            .connect(buyer)
            .exerciseCall(testEIP2981ERC721.address, 0, { value: ONE_ETH });
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await buyer.getAddress()
          );
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          // 0.5ETH premium + 0.5ETH strike (1ETH * 50% creator fee)
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TWO_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TWO_ETH);
      });

      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(testEIP2981ERC721.address, 0);
        }
        it('should transfer NFT to contract', async () => {
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(await buyer.getAddress());
          await run();
          const afterBalance = await weth.balanceOf(await buyer.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(testEIP2981ERC721.address, 0);
          await calls.connect(buyer).exerciseCall(testEIP2981ERC721.address, 0);
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await buyer.getAddress()
          );
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          // 0.5ETH premium + 0.5ETH strike (1ETH * 50% creator fee)
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });
  });

  describe('Vanilla ERC721 NFT', () => {
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

    describe('ETH', () => {
      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );

          await calls
            .connect(buyer)
            .buyCall(testERC721.address, 0, { value: ONE_HALF_ETH });
        }
        it('should transfer NFT to contract', async () => {
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await buyer.getBalance();
          await run();
          const afterBalance = await buyer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            ethers.constants.AddressZero,
            await sellerFundsRecipient.getAddress()
          );

          await calls
            .connect(buyer)
            .buyCall(testERC721.address, 0, { value: ONE_HALF_ETH });

          await calls
            .connect(buyer)
            .exerciseCall(testERC721.address, 0, { value: ONE_ETH });
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await sellerFundsRecipient.getBalance();
          await run();
          const afterBalance = await sellerFundsRecipient.getBalance();

          // 0.5ETH premium + 1ETH strike
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(
            toRoundedNumber(ethers.utils.parseEther('1.5')),
            5
          );
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TWO_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TWO_ETH);
      });

      describe('call option purchased', () => {
        async function run() {
          await calls.createCall(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(testERC721.address, 0);
        }
        it('should transfer NFT to contract', async () => {
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(calls.address);
        });

        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(await buyer.getAddress());
          await run();
          const afterBalance = await weth.balanceOf(await buyer.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('call option exercised', () => {
        async function run() {
          await calls.createCall(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
            weth.address,
            await sellerFundsRecipient.getAddress()
          );
          await calls.connect(buyer).buyCall(testERC721.address, 0);
          await calls.connect(buyer).exerciseCall(testERC721.address, 0);
        }

        it('should transfer NFT to buyer', async () => {
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(await buyer.getAddress());
        });

        it('should transfer strike amount to seller', async () => {
          const beforeBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await sellerFundsRecipient.getAddress()
          );

          // 0.5ETH premium + 1ETH strike
          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(
            toRoundedNumber(ethers.utils.parseEther('1.5')),
            5
          );
        });
      });
    });
  });
});
