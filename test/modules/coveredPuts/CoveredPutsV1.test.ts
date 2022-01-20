import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredPutsV1,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCoveredPutsV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleManager,
  deployProtocolFeeSettings,
  mintZoraNFT,
  ONE_HALF_ETH,
  ONE_ETH,
  registerModule,
  deployZoraProtocol,
  revert,
  toRoundedNumber,
} from '../../utils';
chai.use(asPromised);

describe('CoveredPutsV1', () => {
  let puts: CoveredPutsV1;
  let zoraV1: Media;
  let weth: WETH;
  let deployer: Signer;
  let seller: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    seller = signers[1];
    otherUser = signers[3];

    const zoraV1Protocol = await deployZoraProtocol();
    zoraV1 = zoraV1Protocol.media;
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

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createPut', () => {
    it('should create a covered put option for an NFT', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      const put = await puts.puts(zoraV1.address, 0, 1);

      expect(put.seller).to.eq(await seller.getAddress());
      expect(put.buyer).to.eq(ethers.constants.AddressZero);
      expect(put.currency).to.eq(ethers.constants.AddressZero);
      expect(put.premium.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(put.strike.toString()).to.eq(ONE_ETH.toString());
      expect(put.expiration.toNumber()).to.eq(2526701565);
    });

    it('should revert creating an option for an owned NFT', async () => {
      await expect(
        puts.createPut(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        )
      ).eventually.rejectedWith(
        revert`createPut cannot create put on owned NFT`
      );
    });

    it('should revert creating an option without attaching the strike price', async () => {
      await expect(
        puts.connect(seller).createPut(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should emit a PutCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );
      const events = await puts.queryFilter(
        puts.filters.PutCreated(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = puts.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('PutCreated');
      expect(logDescription.args.putId.toString()).to.eq('1');
      expect(logDescription.args.put.seller).to.eq(await seller.getAddress());
    });
  });

  describe('#cancelPut', () => {
    beforeEach(async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );
    });

    it('should cancel a put not yet purchased', async () => {
      const beforePut = await puts.puts(zoraV1.address, 0, 1);
      expect(beforePut.seller).to.eq(await seller.getAddress());

      await puts.connect(seller).cancelPut(zoraV1.address, 0, 1);

      const afterPut = await puts.puts(zoraV1.address, 0, 1);
      expect(afterPut.seller).to.eq(ethers.constants.AddressZero);
    });

    it('should revert if msg.sender is not the seller', async () => {
      await expect(
        puts.connect(otherUser).cancelPut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('cancelPut must be seller');
    });

    it('should revert if put does not exist', async () => {
      await expect(
        puts.connect(seller).cancelPut(zoraV1.address, 1, 1)
      ).eventually.rejectedWith('cancelPut must be seller');
    });

    it('should revert if put has been purchased', async () => {
      await puts.connect(seller).cancelPut(zoraV1.address, 0, 1);

      await expect(
        puts.connect(seller).cancelPut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('cancelPut must be seller');
    });

    it('should emit a PutCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await puts.connect(seller).cancelPut(zoraV1.address, 0, 1);
      const events = await puts.queryFilter(
        puts.filters.PutCanceled(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = puts.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('PutCanceled');
      expect(logDescription.args.putId.toString()).to.eq('1');
      expect(logDescription.args.put.seller).to.eq(await seller.getAddress());
    });
  });

  describe('#reclaimPut', () => {
    it('should transfer the strike offer back to the seller', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      // Option expired w/o exercise
      await ethers.provider.send('evm_setNextBlockTimestamp', [
        2526701565, // Tue Jan 25 2050 00:32:45 GMT-0500 (Eastern Standard Time)
      ]);

      const beforeBalance = await seller.getBalance();
      await puts.connect(seller).reclaimPut(zoraV1.address, 0, 1);
      const afterBalance = await seller.getBalance();

      expect(
        toRoundedNumber(afterBalance.sub(beforeBalance))
      ).to.be.approximately(toRoundedNumber(ONE_ETH), 10);
    });

    it('should revert if msg.sender is not seller', async () => {
      await expect(
        puts.reclaimPut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('reclaimPut must be seller');
    });

    it('should revert if put has not been purchased', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await expect(
        puts.connect(seller).reclaimPut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('reclaimPut put not purchased');
    });

    it('should revert if put is active', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      await expect(
        puts.connect(seller).reclaimPut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('reclaimPut put is active');
    });
  });

  describe('#buyPut', () => {
    it('should buy a put option', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      const beforeBuyer = await (await puts.puts(zoraV1.address, 0, 1)).buyer;
      expect(beforeBuyer).to.eq(ethers.constants.AddressZero);

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      const afterBuyer = await (await puts.puts(zoraV1.address, 0, 1)).buyer;
      expect(afterBuyer).to.eq(await deployer.getAddress());
    });

    it('should revert buying if put does not exist', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await expect(
        puts.buyPut(zoraV1.address, 1, 1, { value: ONE_HALF_ETH })
      ).eventually.rejectedWith('buyPut put does not exist');
    });

    it('should revert buying if put was already purchased', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      await expect(
        puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH })
      ).eventually.rejectedWith('buyPut put already purchased');
    });

    it('should revert buying if put expired', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526787965, // 	Wed Jan 26 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await ethers.provider.send('evm_setNextBlockTimestamp', [2526787965]);

      await expect(
        puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH })
      ).eventually.rejectedWith('buyPut put expired');
    });
  });

  describe('#exercisePut', () => {
    it('should exercise a put option', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526874365, // Thu Jan 27 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      const beforeBalance = await deployer.getBalance();
      await puts.exercisePut(zoraV1.address, 0, 1);
      const afterBalance = await deployer.getBalance();

      expect(await zoraV1.ownerOf(0)).to.eq(await seller.getAddress());
      expect(
        toRoundedNumber(afterBalance.sub(beforeBalance))
      ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
    });

    it('should revert if msg.sender is not buyer', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526874365, // Thu Jan 27 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      await expect(
        puts.connect(otherUser).exercisePut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('exercisePut must be buyer');
    });

    it('should revert if msg.sender is buyer but does not own token', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526874365, // Thu Jan 27 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts
        .connect(otherUser)
        .buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      await expect(
        puts.connect(otherUser).exercisePut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('exercisePut must own token');
    });

    it('should revert if option expired', async () => {
      await puts.connect(seller).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2526874365, // Thu Jan 27 2050 00:32:45 GMT-0500 (Eastern Standard Time)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      await puts.buyPut(zoraV1.address, 0, 1, { value: ONE_HALF_ETH });

      await ethers.provider.send('evm_setNextBlockTimestamp', [2526874365]);

      await expect(
        puts.exercisePut(zoraV1.address, 0, 1)
      ).eventually.rejectedWith('exercisePut put expired');
    });
  });
});
