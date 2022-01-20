import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { BigNumber, Signer } from 'ethers';
import { Media, Market } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  ReserveAuctionV1,
  RoyaltyEngineV1,
  TestERC721,
  WETH,
} from '../../../typechain';
import {
  approveNFTTransfer,
  bid,
  createReserveAuction,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployReserveAuctionV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleManager,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_DAY,
  ONE_ETH,
  registerModule,
  revert,
  timeTravelToEndOfAuction,
  toRoundedNumber,
  TWO_ETH,
  TENTH_ETH,
  THOUSANDTH_ETH,
  deployProtocolFeeSettings,
  deployTestERC721,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('ReserveAuctionV1', () => {
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let zoraV1Market: Market;
  let weth: WETH;
  let deployer: Signer;
  let bidderA: Signer;
  let bidderB: Signer;
  let sellerFundsRecipient: Signer;
  let otherUser: Signer;
  let finder: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;
  let testERC721: TestERC721;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    const signers = await ethers.getSigners();
    deployer = signers[0];
    bidderA = signers[2];
    bidderB = signers[3];
    sellerFundsRecipient = signers[4];
    otherUser = signers[5];
    finder = signers[6];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    zoraV1Market = zoraProtocol.market;
    royaltyEngine = await deployRoyaltyEngine();
    weth = await deployWETH();
    testERC721 = await deployTestERC721();
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
    reserveAuction = await deployReserveAuctionV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      zoraV1Market.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );

    await registerModule(moduleManager, reserveAuction.address);

    await moduleManager.setApprovalForModule(reserveAuction.address, true);
    await moduleManager
      .connect(bidderA)
      .setApprovalForModule(reserveAuction.address, true);
    await moduleManager
      .connect(bidderB)
      .setApprovalForModule(reserveAuction.address, true);
    await moduleManager
      .connect(otherUser)
      .setApprovalForModule(reserveAuction.address, true);
  });

  describe('#createAuction', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
    });

    it('should revert if the token owner has not approved an auction', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction
          .connect(otherUser)
          .createAuction(
            zoraV1.address,
            0,
            duration,
            reservePrice,
            fundsRecipientAddress,
            findersFeeBps,
            auctionCurrency,
            0
          )
      ).eventually.rejectedWith(
        revert`createAuction must be token owner or operator`
      );
    });

    it('should revert if seller did not approve ERC-721 Transfer Helper', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await otherUser.getAddress(),
        0
      );
      await expect(
        reserveAuction
          .connect(otherUser)
          .createAuction(
            zoraV1.address,
            0,
            duration,
            reservePrice,
            fundsRecipientAddress,
            findersFeeBps,
            auctionCurrency,
            0
          )
      ).eventually.rejectedWith(
        'createAuction must approve ERC721TransferHelper as operator'
      );
    });

    it('should revert if the token ID does not exist', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          zoraV1.address,
          888,
          duration,
          reservePrice,
          fundsRecipientAddress,
          findersFeeBps,
          auctionCurrency,
          0
        )
      ).eventually.rejectedWith('ERC721: owner query for nonexistent token');
    });

    it('should revert if the funds recipient is 0', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;

      const fundsRecipientAddress = ethers.constants.AddressZero;
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          zoraV1.address,
          0,
          duration,
          reservePrice,
          fundsRecipientAddress,
          findersFeeBps,
          auctionCurrency,
          0
        )
      ).eventually.rejectedWith(
        revert`createAuction must specify _sellerFundsRecipient`
      );
    });

    it('should create an auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        0
      );

      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);

      expect(auction.duration.toNumber()).to.eq(duration);
      expect(auction.reservePrice.toString()).to.eq(reservePrice.toString());
      expect(auction.sellerFundsRecipient).to.eq(fundsRecipientAddress);
      expect(auction.seller).to.eq(await deployer.getAddress());
      expect(auction.findersFeeBps.toString()).to.eq(findersFeeBps.toString());
    });

    it('should create a future auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;
      const startTime = 2238366608; // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)

      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        startTime
      );

      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);

      expect(auction.duration.toNumber()).to.eq(duration);
      expect(auction.reservePrice.toString()).to.eq(reservePrice.toString());
      expect(auction.sellerFundsRecipient.toString()).to.eq(
        fundsRecipientAddress.toString()
      );
      expect(auction.seller).to.eq(await deployer.getAddress());
      expect(auction.findersFeeBps.toString()).to.eq(findersFeeBps.toString());
    });

    it('should cancel an old auction if one currently exists for it and create a new one', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        0
      );

      const auction1 = await reserveAuction.auctionForNFT(zoraV1.address, 0);
      expect(auction1.seller).to.eq(await deployer.getAddress());

      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await otherUser.getAddress(),
        0
      );

      await zoraV1
        .connect(otherUser)
        .setApprovalForAll(erc721TransferHelper.address, true);

      await reserveAuction
        .connect(otherUser)
        .createAuction(
          zoraV1.address,
          0,
          duration,
          reservePrice,
          fundsRecipientAddress,
          findersFeeBps,
          auctionCurrency,
          0
        );

      const auction2 = await reserveAuction.auctionForNFT(zoraV1.address, 0);
      expect(auction2.seller).to.eq(await otherUser.getAddress());
    });

    it('should emit an AuctionCreated event', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;
      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const block = await ethers.provider.getBlockNumber();
      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        0
      );

      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);
      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionCreated(null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionCreated');
      expect(logDescription.args.tokenContract.toString()).to.eq(
        zoraV1.address.toString()
      );
      expect(logDescription.args.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.auction.duration.toNumber()).to.eq(
        auction.duration.toNumber()
      );
      expect(logDescription.args.auction.reservePrice.toString()).to.eq(
        auction.reservePrice.toString()
      );
      expect(logDescription.args.auction.sellerFundsRecipient).to.eq(
        auction.sellerFundsRecipient
      );
      expect(logDescription.args.auction.auctionCurrency).to.eq(
        ethers.constants.AddressZero
      );
    });
  });

  describe('#setAuctionReservePrice', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await deployer.getAddress(),
        10,
        ethers.constants.AddressZero
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.setAuctionReservePrice(zoraV1.address, 2, 1)
      ).eventually.rejectedWith('setAuctionReservePrice must be seller');
    });

    it('should revert if the caller is not the owner or operator', async () => {
      await expect(
        reserveAuction
          .connect(otherUser)
          .setAuctionReservePrice(zoraV1.address, 0, 1)
      ).eventually.rejectedWith(revert`setAuctionReservePrice must be seller`);
    });

    it('should revert if the auction has already started', async () => {
      await bid(
        reserveAuction,
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await expect(
        reserveAuction.setAuctionReservePrice(zoraV1.address, 0, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice auction has already started`
      );
    });

    it('should set the reserve price for the auction', async () => {
      await reserveAuction.setAuctionReservePrice(
        zoraV1.address,
        0,
        ONE_ETH.mul(2)
      );
      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);

      expect(auction.reservePrice.toString()).to.eq(ONE_ETH.mul(2).toString());
    });

    it('should emit an AuctionReservePriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.setAuctionReservePrice(
        zoraV1.address,
        0,
        ONE_ETH.mul(2)
      );

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionReservePriceUpdated(
          null,
          null,
          null,
          null
        ),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionReservePriceUpdated');

      expect(logDescription.args.reservePrice.toString()).to.eq(
        TWO_ETH.toString()
      );
      expect(logDescription.args.auction.reservePrice.toString()).to.eq(
        TWO_ETH.toString()
      );
      expect(logDescription.args.tokenContract).to.eq(zoraV1.address);
      expect(logDescription.args.tokenId.toString()).to.eq('0');
    });
  });

  describe('#createBid', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await sellerFundsRecipient.getAddress(),
        10
      );
    });

    it('should revert if the auction expired', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0, true);

      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(
            zoraV1.address,
            0,
            ONE_ETH.mul(2),
            await finder.getAddress()
          )
      ).eventually.rejectedWith(revert`createBid auction expired`);
    });

    it('should revert if the auction has not started', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;

      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const startTime = 2238366608; // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)

      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        startTime
      );

      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(
            zoraV1.address,
            0,
            ONE_ETH.mul(2),
            await finder.getAddress()
          )
      ).eventually.rejectedWith(revert`createBid auction hasn't started`);
    });

    it('should revert if the bid does not meet the reserve price', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(zoraV1.address, 0, 1, await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid must send at least reservePrice`
      );
    });

    it('should revert if the bid is not greater than 10% more of the previous bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(
            zoraV1.address,
            0,
            ONE_ETH.add(1),
            await finder.getAddress()
          )
      ).eventually.rejectedWith(
        revert`createBid must send more than the last bid by minBidIncrementPercentage amount`
      );
    });

    it('should revert if the bid is invalid on zora v1', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(
            zoraV1.address,
            0,
            ONE_ETH.add(1),
            await finder.getAddress()
          )
      ).eventually.rejectedWith(
        revert`createBid bid invalid for share splitting`
      );
    });

    it('should set the starting time on the first bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
    });

    it('should refund the previous bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(
        await bidderA.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderB),
        zoraV1.address,
        0,
        ONE_ETH.mul(2),
        await finder.getAddress()
      );

      const afterBalance = await ethers.provider.getBalance(
        await bidderA.getAddress()
      );

      expect(toRoundedNumber(afterBalance)).to.approximately(
        toRoundedNumber(beforeBalance),
        5
      );
    });

    it('should accept the transfer and set the bid details on the auction', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
      expect(auction.amount.toString()).to.eq(ONE_ETH.toString());
      expect(auction.bidder).to.eq(await bidderA.getAddress());
      expect(
        (await ethers.provider.getBalance(reserveAuction.address)).toString()
      ).to.eq(ONE_ETH.toString());
    });

    it('should extend the auction if it is in its final moments', async () => {
      const oldDuration = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).duration;
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0);
      await bid(
        reserveAuction.connect(bidderB),
        zoraV1.address,
        0,
        TWO_ETH,
        await finder.getAddress()
      );
      const newDuration = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).duration;

      expect(newDuration.toNumber()).to.eq(
        oldDuration.toNumber() - 1 + 15 * 60
      );
    });

    it('should set the current finder on the auction', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const auction = await reserveAuction.auctionForNFT(zoraV1.address, 0);
      expect(auction.finder).to.eq(await finder.getAddress());
    });

    it('should revert if the auction creator transfers the token before the first bid', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await otherUser.getAddress(),
        0
      );
      await expect(
        bid(
          reserveAuction.connect(bidderA),
          zoraV1.address,
          0,
          ONE_ETH,
          await finder.getAddress()
        )
      ).eventually.rejectedWith(
        revert`ERC721: transfer caller is not owner nor approved`
      );
    });

    it('should create the first bid on a future auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const findersFeeBps = 1000;

      const fundsRecipientAddress = await sellerFundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const startTime = 2238366608; // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)

      await reserveAuction.createAuction(
        zoraV1.address,
        0,
        duration,
        reservePrice,
        fundsRecipientAddress,
        findersFeeBps,
        auctionCurrency,
        startTime
      );

      // await ethers.provider.send('evm_increaseTime', [startTime]);
      await ethers.provider.send('evm_setNextBlockTimestamp', [2238366608]);

      await reserveAuction
        .connect(bidderB)
        .createBid(zoraV1.address, 0, TWO_ETH, await finder.getAddress(), {
          value: TWO_ETH,
        });

      const createdAuction = await reserveAuction.auctionForNFT(
        zoraV1.address,
        0
      );
      expect(createdAuction.firstBidTime.toNumber()).to.not.eq(0);
    });

    it('should emit an AuctionBid event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionBid(null, null, null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionBid');

      expect(logDescription.args.amount.toString()).to.eq(ONE_ETH.toString());
      expect(logDescription.args.bidder).to.eq(await bidderA.getAddress());
      expect(logDescription.args.firstBid).to.eq(true);
      expect(logDescription.args.extended).to.eq(false);
    });

    it('should emit an AuctionDurationExtended event', async () => {
      const oldDuration = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).duration;
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0);

      const block = await ethers.provider.getBlockNumber();

      await bid(
        reserveAuction.connect(bidderB),
        zoraV1.address,
        0,
        TWO_ETH,
        await finder.getAddress()
      );

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionDurationExtended(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionDurationExtended');

      expect(logDescription.args.duration.toNumber()).to.eq(
        oldDuration.toNumber() - 1 + 15 * 60
      );
    });
  });

  describe('#cancelAuction', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await reserveAuction
        .connect(deployer)
        .createAuction(
          zoraV1.address,
          0,
          ONE_DAY,
          TENTH_ETH,
          await sellerFundsRecipient.getAddress(),
          1000,
          ethers.constants.AddressZero,
          0
        );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.cancelAuction(zoraV1.address, 1111)
      ).eventually.rejectedWith(revert`cancelAuction auction doesn't exist`);
    });

    it('should revert if not called by the listingFeeRecipient or creator before the first bid', async () => {
      await expect(
        reserveAuction.connect(otherUser).cancelAuction(zoraV1.address, 0)
      ).eventually.rejectedWith(
        revert`cancelAuction must be token owner or operator`
      );
    });

    it('should revert if the auction has started', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        zoraV1.address,
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      await expect(
        reserveAuction.cancelAuction(zoraV1.address, 0)
      ).eventually.rejectedWith(revert`cancelAuction auction already started`);
    });

    it('should cancel an auction', async () => {
      await reserveAuction.cancelAuction(zoraV1.address, 0);

      const deletedAuction = await reserveAuction.auctionForNFT(
        zoraV1.address,
        0
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await deployer.getAddress());
      expect(deletedAuction.seller).to.eq(ethers.constants.AddressZero);
    });

    it('should emit an AuctionCanceled event', async () => {
      await reserveAuction.cancelAuction(zoraV1.address, 0);

      const block = await ethers.provider.getBlockNumber();

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionCanceled(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionCanceled');

      expect(logDescription.args.tokenContract.toString()).to.eq(
        zoraV1.address.toString()
      );
      expect(logDescription.args.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.auction.finder.toString()).to.eq(
        ethers.constants.AddressZero
      );
    });
  });

  describe('#settleAuction', async () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);

      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [ONE_ETH.div(2)]
      );

      await reserveAuction
        .connect(deployer)
        .createAuction(
          zoraV1.address,
          0,
          ONE_DAY,
          TENTH_ETH,
          await sellerFundsRecipient.getAddress(),
          1000,
          ethers.constants.AddressZero,
          0
        );
    });

    it('should settle an auction', async () => {
      const bidderBeforeBalance = await bidderA.getBalance();
      const sellerFundsRecipientBeforeBalance =
        await sellerFundsRecipient.getBalance();
      const finderBeforeBalance = await finder.getBalance();

      await reserveAuction
        .connect(bidderA)
        .createBid(zoraV1.address, 0, ONE_ETH, await finder.getAddress(), {
          value: ONE_ETH,
        });

      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0, true);
      await reserveAuction.connect(otherUser).settleAuction(zoraV1.address, 0);

      const bidderAfterBalance = await bidderA.getBalance();
      const sellerFundsRecipientAfterBalance =
        await sellerFundsRecipient.getBalance();
      const finderAfterBalance = await finder.getBalance();

      // 1 ETH bid
      expect(toRoundedNumber(bidderAfterBalance)).to.approximately(
        toRoundedNumber(bidderBeforeBalance.sub(ONE_ETH)),
        5
      );

      // 0.5ETH creator fee * 1 ETH bid * 10% finder fee = 0.05 ETH
      expect(toRoundedNumber(finderAfterBalance)).to.eq(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(50)))
      );

      // 0.5 ETH creator fee - 0.05 ETH finder fee -> .45 ETH profit
      expect(toRoundedNumber(sellerFundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          sellerFundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(450))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await bidderA.getAddress());
    });

    it('should revert if the auction has not begun', async () => {
      await expect(
        reserveAuction.settleAuction(zoraV1.address, 0)
      ).eventually.rejectedWith(revert`settleAuction auction hasn't begun`);
    });

    it('should revert if the auction has not completed', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(zoraV1.address, 0, ONE_ETH, await finder.getAddress(), {
          value: ONE_ETH,
        });

      await expect(
        reserveAuction.settleAuction(zoraV1.address, 0)
      ).eventually.rejectedWith(revert`settleAuction auction hasn't completed`);
    });

    it('should emit an AuctionEnded event', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(zoraV1.address, 0, ONE_ETH, await finder.getAddress(), {
          value: ONE_ETH,
        });
      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0, true);

      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.connect(otherUser).settleAuction(zoraV1.address, 0);

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionEnded(null, null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionEnded');

      expect(logDescription.args.winner).to.eq(await bidderA.getAddress());
      expect(logDescription.args.finder).to.eq(await finder.getAddress());

      expect(logDescription.args.auction.amount.toString()).to.eq(
        ONE_ETH.toString()
      );
      expect(logDescription.args.auction.findersFeeBps.toString()).to.eq(
        '1000'
      );
    });

    it('should emit an ExchangeExecuted event', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(zoraV1.address, 0, ONE_ETH, await finder.getAddress(), {
          value: ONE_ETH,
        });
      await timeTravelToEndOfAuction(reserveAuction, zoraV1.address, 0, true);

      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.connect(otherUser).settleAuction(zoraV1.address, 0);

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.ExchangeExecuted(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ExchangeExecuted');

      expect(logDescription.args.userA).to.eq(await deployer.getAddress());
      expect(logDescription.args.userB).to.eq(await bidderA.getAddress());

      expect(logDescription.args.a.tokenContract.toString()).to.eq(
        zoraV1.address.toString()
      );
      expect(logDescription.args.a.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.a.amount.toNumber()).to.eq(1);

      expect(logDescription.args.b.tokenContract.toString()).to.eq(
        ethers.constants.AddressZero.toString()
      );
      expect(logDescription.args.b.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.b.amount.toString()).to.eq(ONE_ETH.toString());
    });
  });
});
