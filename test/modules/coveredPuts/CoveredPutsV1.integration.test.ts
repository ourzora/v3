import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { providers, Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredPutsV1,
  WETH,
  TestEIP2981ERC721,
  TestERC721,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCoveredPutsV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC721,
  deployWETH,
  deployZoraModuleManager,
  deployProtocolFeeSettings,
  mintZoraNFT,
  mintERC2981Token,
  mintERC721Token,
  ONE_HALF_ETH,
  ONE_ETH,
  registerModule,
  deployZoraProtocol,
  toRoundedNumber,
  THOUSANDTH_ETH,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('CoveredPutsV1', () => {
  let puts: CoveredPutsV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let seller: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    seller = signers[1];
    buyer = signers[2];
    otherUser = signers[3];

    const zoraV1Protocol = await deployZoraProtocol();
    zoraV1 = zoraV1Protocol.media;
    testERC721 = await deployTestERC721();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    weth = await deployWETH();
    const feeSettings = await deployProtocolFeeSettings();
    const moduleManager = await deployZoraModuleManager(
      await deployer.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(moduleManager.address, zoraV1.address);
    erc20TransferHelper = await deployERC20TransferHelper(
      moduleManager.address
    );
    erc721TransferHelper = await deployERC721TransferHelper(
      moduleManager.address
    );
    royaltyEngine = await deployRoyaltyEngine();
    puts = await deployCoveredPutsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );

    await registerModule(moduleManager, puts.address);

    await moduleManager.setApprovalForModule(puts.address, true);
    await moduleManager
      .connect(seller)
      .setApprovalForModule(puts.address, true);
    await moduleManager
      .connect(otherUser)
      .setApprovalForModule(puts.address, true);
  });

  describe('ZORA V1 NFT', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    describe('ETH', () => {
      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await seller.getBalance();
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await deployer.getBalance();
          await run();
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const beforeBalance = await seller.getBalance();
          await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });
          await puts.exercisePut(zoraV1.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await zoraV1.ownerOf(0)).to.eq(await deployer.getAddress());
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

          const beforeBalance = await deployer.getBalance();
          await puts.exercisePut(zoraV1.address, 0, 1);
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        // Seller approve 1 ETH strike offer
        await weth.connect(seller).deposit({ value: ONE_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, ONE_ETH);

        // Buyer approve 0.5 ETH premium price
        await weth.connect(deployer).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(deployer)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
      });

      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(zoraV1.address, 0, 1);
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.buyPut(zoraV1.address, 0, 1);
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(zoraV1.address, 0, 1);
          await puts.exercisePut(zoraV1.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await zoraV1.ownerOf(0)).to.eq(await deployer.getAddress());
          await run();
          expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            zoraV1.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(zoraV1.address, 0, 1);

          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await puts.exercisePut(zoraV1.address, 0, 1);
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
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
        erc721TransferHelper.address
      );
    });

    describe('ETH', () => {
      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await seller.getBalance();
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1, {
            value: ONE_HALF_ETH,
          });
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await deployer.getBalance();
          await run();
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const beforeBalance = await seller.getBalance();
          await puts.buyPut(testEIP2981ERC721.address, 0, 1, {
            value: ONE_HALF_ETH,
          });
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1, {
            value: ONE_HALF_ETH,
          });
          await puts.exercisePut(testEIP2981ERC721.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await deployer.getAddress()
          );
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await seller.getAddress()
          );
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1, {
            value: ONE_HALF_ETH,
          });

          const beforeBalance = await deployer.getBalance();
          await puts.exercisePut(testEIP2981ERC721.address, 0, 1);
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        // Seller approve 1 ETH strike offer
        await weth.connect(seller).deposit({ value: ONE_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, ONE_ETH);

        // Buyer approve 0.5 ETH premium price
        await weth.connect(deployer).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(deployer)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
      });

      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1);
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.buyPut(testEIP2981ERC721.address, 0, 1);
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1);
          await puts.exercisePut(testEIP2981ERC721.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await deployer.getAddress()
          );
          await run();
          expect(await testEIP2981ERC721.ownerOf(0)).to.eq(
            await seller.getAddress()
          );
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            testEIP2981ERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testEIP2981ERC721.address, 0, 1);

          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await puts.exercisePut(testEIP2981ERC721.address, 0, 1);
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

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
        erc721TransferHelper.address
      );
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [0]
      );
    });

    describe('ETH', () => {
      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await seller.getBalance();
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testERC721.address, 0, 1, { value: ONE_HALF_ETH });
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await deployer.getBalance();
          await run();
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          const beforeBalance = await seller.getBalance();
          await puts.buyPut(testERC721.address, 0, 1, { value: ONE_HALF_ETH });
          const afterBalance = await seller.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testERC721.address, 0, 1, { value: ONE_HALF_ETH });
          await puts.exercisePut(testERC721.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await testERC721.ownerOf(0)).to.eq(
            await deployer.getAddress()
          );
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(await seller.getAddress());
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );
          await puts.buyPut(testERC721.address, 0, 1, { value: ONE_HALF_ETH });

          const beforeBalance = await deployer.getBalance();
          await puts.exercisePut(testERC721.address, 0, 1);
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });

    describe('WETH', () => {
      beforeEach(async () => {
        // Seller approve 1 ETH strike offer
        await weth.connect(seller).deposit({ value: ONE_ETH });
        await weth
          .connect(seller)
          .approve(erc20TransferHelper.address, ONE_ETH);

        // Buyer approve 0.5 ETH premium price
        await weth.connect(deployer).deposit({ value: ONE_HALF_ETH });
        await weth
          .connect(deployer)
          .approve(erc20TransferHelper.address, ONE_HALF_ETH);
      });

      describe('put option created', () => {
        it('should withdraw strike offer from seller', async () => {
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });

      describe('put option purchased', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testERC721.address, 0, 1);
        }
        it('should withdraw premium from buyer', async () => {
          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await run();
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium to seller', async () => {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          const beforeBalance = await weth.balanceOf(await seller.getAddress());
          await puts.buyPut(testERC721.address, 0, 1);
          const afterBalance = await weth.balanceOf(await seller.getAddress());

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });

      describe('put option exercised', () => {
        async function run() {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testERC721.address, 0, 1);
          await puts.exercisePut(testERC721.address, 0, 1);
        }

        it('should transfer NFT to seller', async () => {
          expect(await testERC721.ownerOf(0)).to.eq(
            await deployer.getAddress()
          );
          await run();
          expect(await testERC721.ownerOf(0)).to.eq(await seller.getAddress());
        });

        it('should transfer strike to buyer', async () => {
          await puts.connect(seller).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2526269565, // Thu Jan 20 2050 00:32:45 GMT-0500 (Eastern Standard Time)
            weth.address
          );
          await puts.buyPut(testERC721.address, 0, 1);

          const beforeBalance = await weth.balanceOf(
            await deployer.getAddress()
          );
          await puts.exercisePut(testERC721.address, 0, 1);
          const afterBalance = await weth.balanceOf(
            await deployer.getAddress()
          );

          expect(
            toRoundedNumber(afterBalance.sub(beforeBalance))
          ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
        });
      });
    });
  });
});
