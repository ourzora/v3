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
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_DAY,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
  timeTravelToEndOfAuction,
  toRoundedNumber,
  TWO_ETH,
  TENTH_ETH,
  THOUSANDTH_ETH,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('ReserveAuctionV1', () => {
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let zoraV1Market: Market;
  let weth: WETH;
  let deployer: Signer;
  let listingFeeRecipient: Signer;
  let bidderA: Signer;
  let bidderB: Signer;
  let fundsRecipient: Signer;
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
    fundsRecipient = signers[4];
    otherUser = signers[5];
    finder = signers[6];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    zoraV1Market = zoraProtocol.market;
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
      .connect(bidderA)
      .setApprovalForModule(reserveAuction.address, true);
    await approvalManager
      .connect(bidderB)
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
      const listingFeePercentage = 15;
      const findersFeePercentage = 10;
      const listingFeeRecipient = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction
          .connect(otherUser)
          .createAuction(
            0,
            zoraV1.address,
            duration,
            reservePrice,
            listingFeeRecipient,
            fundsRecipientAddress,
            listingFeePercentage,
            findersFeePercentage,
            auctionCurrency,
            0
          )
      ).eventually.rejectedWith(
        revert`createAuction must be token owner or approved operator`
      );
    });

    it('should revert if the token ID does not exist', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 15;
      const findersFeePercentage = 10;
      const listingFeeRecipient = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          888,
          zoraV1.address,
          duration,
          reservePrice,
          listingFeeRecipient,
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency,
          0
        )
      ).eventually.rejectedWith('ERC721: owner query for nonexistent token');
    });

    it('should revert if the listingFeeRecipient fee percentage is >= 100', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 100;
      const findersFeePercentage = 10;
      const listingFeeRecipient = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          0,
          zoraV1.address,
          duration,
          reservePrice,
          listingFeeRecipient,
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency,
          0
        )
      ).eventually.rejectedWith(
        revert`createAuction _listingFeePercentage plus _findersFeePercentage must be less than 100`
      );
    });

    it('should revert if the funds recipient is 0', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;

      const fundsRecipientAddress = ethers.constants.AddressZero;
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          0,
          zoraV1.address,
          duration,
          reservePrice,
          await listingFeeRecipient.getAddress(),
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency,
          0
        )
      ).eventually.rejectedWith(
        revert`createAuction _fundsRecipient cannot be 0 address`
      );
    });

    it('should create an auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;

      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        0
      );

      const createdAuction = await reserveAuction.auctions(1);
      const createdFees = await reserveAuction.fees(1);
      const auctionId = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).toNumber();
      expect(createdAuction.duration.toNumber()).to.eq(duration);
      expect(createdAuction.reservePrice.toString()).to.eq(
        reservePrice.toString()
      );
      expect(createdFees.listingFeePercentage).to.eq(listingFeePercentage);
      expect(createdFees.listingFeeRecipient).to.eq(
        await listingFeeRecipient.getAddress()
      );
      expect(createdAuction.fundsRecipient).to.eq(fundsRecipientAddress);
      expect(createdAuction.seller).to.eq(await deployer.getAddress());
      expect(createdFees.findersFeePercentage).to.eq(findersFeePercentage);
      expect(auctionId).to.eq(1);
    });

    it('should create a future auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;

      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const startTime = 3600; // in 1 hr

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        startTime
      );

      const createdAuction = await reserveAuction.auctions(1);
      const createdFees = await reserveAuction.fees(1);
      const auctionId = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).toNumber();
      expect(createdAuction.duration.toNumber()).to.eq(duration);
      expect(createdAuction.reservePrice.toString()).to.eq(
        reservePrice.toString()
      );
      expect(createdFees.listingFeePercentage).to.eq(listingFeePercentage);
      expect(createdFees.listingFeeRecipient).to.eq(
        await listingFeeRecipient.getAddress()
      );
      expect(createdAuction.fundsRecipient).to.eq(fundsRecipientAddress);
      expect(createdAuction.seller).to.eq(await deployer.getAddress());
      expect(createdFees.findersFeePercentage).to.eq(findersFeePercentage);
      expect(auctionId).to.eq(1);
    });

    it('should cancel an old auction if one currently exists for it and create a new one', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      expect(
        (await reserveAuction.auctionForNFT(zoraV1.address, 0)).toString()
      ).to.eq('0');

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        0
      );

      expect(
        (await reserveAuction.auctionForNFT(zoraV1.address, 0)).toString()
      ).to.eq('1');

      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await otherUser.getAddress(),
        0
      );

      await reserveAuction.connect(otherUser).cancelAuction(1);

      expect(
        (await reserveAuction.auctionForNFT(zoraV1.address, 0)).toString()
      ).to.eq('0');

      await reserveAuction
        .connect(otherUser)
        .createAuction(
          0,
          zoraV1.address,
          duration,
          reservePrice,
          await listingFeeRecipient.getAddress(),
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency,
          0
        );

      const oldAuction = await reserveAuction.auctions(1);
      const newAuction = await reserveAuction.auctions(2);
      const auctionId = (
        await reserveAuction.auctionForNFT(zoraV1.address, 0)
      ).toNumber();
      expect(auctionId).to.eq(2);
      expect(oldAuction.tokenContract).to.eq(ethers.constants.AddressZero);
      expect(newAuction.tokenContract).to.eq(zoraV1.address);
      expect(newAuction.seller).to.eq(await otherUser.getAddress());
    });

    it('should emit an AuctionCreated event', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const block = await ethers.provider.getBlockNumber();
      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        0
      );

      const createdAuction = await reserveAuction.auctions(1);
      const createdAuctionFees = await reserveAuction.fees(1);
      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.auction.tokenId.toNumber()).to.eq(
        createdAuction.tokenId.toNumber()
      );
      expect(logDescription.args.auction.tokenContract).to.eq(
        createdAuction.tokenContract
      );
      expect(logDescription.args.auction.duration.toNumber()).to.eq(
        createdAuction.duration.toNumber()
      );
      expect(logDescription.args.auction.reservePrice.toString()).to.eq(
        createdAuction.reservePrice.toString()
      );
      expect(logDescription.args.fees.listingFeeRecipient).to.eq(
        createdAuctionFees.listingFeeRecipient
      );
      expect(logDescription.args.auction.fundsRecipient).to.eq(
        createdAuction.fundsRecipient
      );
      expect(logDescription.args.fees.listingFeePercentage).to.eq(
        createdAuctionFees.listingFeePercentage
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
        await listingFeeRecipient.getAddress(),
        10,
        ethers.constants.AddressZero
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.setAuctionReservePrice(111, 1)
      ).eventually.rejectedWith();
    });

    it('should revert if the caller is not the owner or listingFeeRecipient', async () => {
      await expect(
        reserveAuction.connect(otherUser).setAuctionReservePrice(1, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice must be token owner`
      );
    });

    it('should revert if the auction has already started', async () => {
      await bid(reserveAuction, 1, ONE_ETH, await finder.getAddress());
      await expect(
        reserveAuction.setAuctionReservePrice(1, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice auction has already started`
      );
    });

    it('should set the reserve price for the auction', async () => {
      await reserveAuction.setAuctionReservePrice(1, ONE_ETH.mul(2));
      const auction = await reserveAuction.auctions(1);

      expect(auction.reservePrice.toString()).to.eq(ONE_ETH.mul(2).toString());
    });

    it('should emit an AuctionReservePriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.setAuctionReservePrice(1, ONE_ETH.mul(2));

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionReservePriceUpdated(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionReservePriceUpdated');

      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.reservePrice.toString()).to.eq(
        TWO_ETH.toString()
      );

      expect(logDescription.args.auction.reservePrice.toString()).to.eq(
        TWO_ETH.toString()
      );
      expect(logDescription.args.auction.tokenContract).to.eq(
        zoraV1.address.toString()
      );
      expect(logDescription.args.auction.tokenId.toNumber()).to.eq(0);
    });
  });

  describe('#createBid', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await fundsRecipient.getAddress(),
        ethers.constants.AddressZero,
        10,
        undefined
      );
    });

    it('should revert if the auction expired', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 1, true);

      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH.mul(2), await finder.getAddress())
      ).eventually.rejectedWith(revert`createBid auction expired`);
    });

    it('should revert if the auction has not started', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;

      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const startTime = 3600; // in 1 hr

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        startTime
      );

      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(2, ONE_ETH.mul(2), await finder.getAddress())
      ).eventually.rejectedWith(revert`createBid auction hasn't started`);
    });

    it('should revert if the bid does not meet the reserve price', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(1, 1, await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid must send at least reservePrice`
      );
    });

    it('should revert if the bid is not greater than 10% more of the previous bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH.add(1), await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid must send more than the last bid by minBidIncrementPercentage amount`
      );
    });

    it('should revert if the _finder is zero address', async () => {
      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(1, ONE_ETH, ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`createBid _finder must not be 0 address`
      );
    });

    it('should revert if the bid is invalid on zora v1', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(1, ONE_ETH.add(1), await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid bid invalid for share splitting`
      );
    });

    it('should set the starting time on the first bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      const auction = await reserveAuction.auctions(1);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
    });

    it('should refund the previous bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(
        await bidderA.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderB),
        1,
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
        1,
        ONE_ETH,
        await finder.getAddress()
      );

      const auction = await reserveAuction.auctions(1);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
      expect(auction.amount.toString()).to.eq(ONE_ETH.toString());
      expect(auction.bidder).to.eq(await bidderA.getAddress());
      expect(
        (await ethers.provider.getBalance(reserveAuction.address)).toString()
      ).to.eq(ONE_ETH.toString());
    });

    it('should extend the auction if it is in its final moments', async () => {
      const oldDuration = (await reserveAuction.auctions(1)).duration;
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 1);
      await bid(
        reserveAuction.connect(bidderB),
        1,
        TWO_ETH,
        await finder.getAddress()
      );
      const newDuration = (await reserveAuction.auctions(1)).duration;

      expect(newDuration.toNumber()).to.eq(
        oldDuration.toNumber() - 1 + 15 * 60
      );
    });

    it('should set the current finder on the auction', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );

      const currFinder = (await reserveAuction.fees(1)).finder;

      expect(currFinder).to.eq(await finder.getAddress());
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
          1,
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
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;

      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const startTime = 3600; // in 1 hr

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        await listingFeeRecipient.getAddress(),
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency,
        startTime
      );

      await ethers.provider.send('evm_increaseTime', [startTime]);

      await reserveAuction
        .connect(bidderB)
        .createBid(2, TWO_ETH, await finder.getAddress(), {
          value: TWO_ETH,
        });

      const createdAuction = await reserveAuction.auctions(2);
      expect(createdAuction.firstBidTime.toNumber()).to.not.eq(0);
    });

    it('should emit an AuctionBid event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await bid(
        reserveAuction.connect(bidderA),
        1,
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

      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.bidder).to.eq(await bidderA.getAddress());
      expect(logDescription.args.amount.toString()).to.eq(ONE_ETH.toString());
      expect(logDescription.args.firstBid).to.eq(true);
      expect(logDescription.args.extended).to.eq(false);
    });

    it('should emit an AuctionDurationExtended event', async () => {
      const oldDuration = (await reserveAuction.auctions(1)).duration;
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 1);

      const block = await ethers.provider.getBlockNumber();

      await bid(
        reserveAuction.connect(bidderB),
        1,
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

      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.duration.toNumber()).to.eq(
        oldDuration.toNumber() - 1 + 15 * 60
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
          0,
          zoraV1.address,
          ONE_DAY,
          TENTH_ETH,
          await listingFeeRecipient.getAddress(),
          await fundsRecipient.getAddress(),
          10,
          10,
          ethers.constants.AddressZero,
          0
        );
    });

    it('should settle an auction', async () => {
      const bidderBeforeBalance = await bidderA.getBalance();
      const sellerFundsRecipientBeforeBalance =
        await fundsRecipient.getBalance();
      const listingFeeRecipientBeforeBalance =
        await listingFeeRecipient.getBalance();
      const finderBeforeBalance = await finder.getBalance();

      await reserveAuction
        .connect(bidderA)
        .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });

      await timeTravelToEndOfAuction(reserveAuction, 1, true);
      await reserveAuction.connect(otherUser).settleAuction(1);

      const bidderAfterBalance = await bidderA.getBalance();
      const sellerFundsRecipientAfterBalance =
        await fundsRecipient.getBalance();
      const listingFeeRecipientAfterBalance =
        await listingFeeRecipient.getBalance();
      const finderAfterBalance = await finder.getBalance();

      // 1 ETH bid
      expect(toRoundedNumber(bidderAfterBalance)).to.approximately(
        toRoundedNumber(bidderBeforeBalance.sub(ONE_ETH)),
        5
      );
      // 0.5ETH creator fee * 1 ETH bid * 10% listing fee = 0.05 ETH
      expect(toRoundedNumber(listingFeeRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          listingFeeRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(50))
        )
      );
      // 0.5ETH creator fee * 1 ETH bid * 10% finder fee = 0.05 ETH
      expect(toRoundedNumber(finderAfterBalance)).to.eq(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(50)))
      );

      // 0.5 ETH creator fee - 0.05 ETH listing fee - 0.05 ETH finder fee -> .4 ETH profit
      expect(toRoundedNumber(sellerFundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          sellerFundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(400))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await bidderA.getAddress());
    });

    it('should revert if the auction has not begun', async () => {
      await expect(reserveAuction.settleAuction(1)).eventually.rejectedWith(
        revert`settleAuction auction hasn't begun`
      );
    });

    it('should revert if the auction has not completed', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });

      await expect(reserveAuction.settleAuction(1)).eventually.rejectedWith(
        revert`settleAuction auction hasn't completed`
      );
    });

    it('should emit an AuctionEnded event', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
      await timeTravelToEndOfAuction(reserveAuction, 1, true);

      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.connect(otherUser).settleAuction(1);

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionEnded(null, null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionEnded');

      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.winner).to.eq(await bidderA.getAddress());
      expect(logDescription.args.finder).to.eq(await finder.getAddress());

      expect(logDescription.args.auction.amount.toString()).to.eq(
        ONE_ETH.toString()
      );
      expect(logDescription.args.fees.listingFeePercentage).to.eq(10);
      expect(logDescription.args.fees.findersFeePercentage).to.eq(10);
    });

    it('should emit an ExchangeExecuted event', async () => {
      await reserveAuction
        .connect(bidderA)
        .createBid(1, ONE_ETH, await finder.getAddress(), { value: ONE_ETH });
      await timeTravelToEndOfAuction(reserveAuction, 1, true);

      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.connect(otherUser).settleAuction(1);

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

  describe('#cancelAuction', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await reserveAuction
        .connect(deployer)
        .createAuction(
          0,
          zoraV1.address,
          ONE_DAY,
          TENTH_ETH,
          await listingFeeRecipient.getAddress(),
          await fundsRecipient.getAddress(),
          10,
          10,
          ethers.constants.AddressZero,
          0
        );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(reserveAuction.cancelAuction(1111)).eventually.rejectedWith(
        revert`cancelAuction auction doesn't exist`
      );
    });

    it('should revert if not called by the listingFeeRecipient or creator before the first bid', async () => {
      await expect(
        reserveAuction.connect(otherUser).cancelAuction(1)
      ).eventually.rejectedWith(
        revert`cancelAuction must be auction creator or invalid auction`
      );
    });

    it('should revert if the auction has started', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );

      await expect(reserveAuction.cancelAuction(1)).eventually.rejectedWith(
        revert`cancelAuction auction already started`
      );
    });

    it('should cancel an auction', async () => {
      await reserveAuction.cancelAuction(1);

      const deletedAuction = await reserveAuction.auctions(1);

      expect(await zoraV1.ownerOf(0)).to.eq(await deployer.getAddress());
      expect(deletedAuction.tokenContract).to.eq(ethers.constants.AddressZero);
      expect(deletedAuction.seller).to.eq(ethers.constants.AddressZero);
    });

    it('should emit an AuctionCanceled event', async () => {
      await reserveAuction.cancelAuction(1);

      const block = await ethers.provider.getBlockNumber();

      const events = await reserveAuction.queryFilter(
        reserveAuction.filters.AuctionCanceled(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionCanceled');

      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.auction.tokenContract.toString()).to.eq(
        zoraV1.address.toString()
      );
      expect(logDescription.args.auction.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.fees.finder.toString()).to.eq(
        ethers.constants.AddressZero
      );
    });
  });
});
