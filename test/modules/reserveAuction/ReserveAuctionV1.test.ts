import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  BadErc721,
  Erc20TransferHelper,
  Erc721TransferHelper,
  LibReserveAuctionV1Factory,
  ReserveAuctionV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
} from '../../../typechain';

import {
  approveNFTTransfer,
  bid,
  createReserveAuction,
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
  settleAuction,
  mintERC2981Token,
  mintERC721Token,
  mintZoraNFT,
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

import { BigNumber, Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';

chai.use(asPromised);

describe('ReserveAuctionV1', () => {
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
    finder = signers[6];
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

    it('should revert if the 721 token does not support the ERC721 interface', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);

      await expect(
        reserveAuction.createAuction(
          0,
          badERC721.address,
          duration,
          reservePrice,
          await host.getAddress(),
          await fundsRecipient.getAddress(),
          5,
          10,
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith(
        revert`createAuction tokenContract does not support ERC721 interface`
      );
    });

    it('should revert if the token owner has not approved an auction', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 15;
      const findersFeePercentage = 10;
      const host = ethers.constants.AddressZero;
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
            host,
            fundsRecipientAddress,
            listingFeePercentage,
            findersFeePercentage,
            auctionCurrency
          )
      ).eventually.rejectedWith(
        revert`createAuction caller must be approved or owner for token id`
      );
    });

    it('should revert if the token ID does not exist', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 15;
      const findersFeePercentage = 10;
      const host = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          888,
          zoraV1.address,
          duration,
          reservePrice,
          host,
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith('ERC721: owner query for nonexistent token');
    });

    it('should revert if the host fee percentage is >= 100', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 100;
      const findersFeePercentage = 10;
      const host = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          0,
          zoraV1.address,
          duration,
          reservePrice,
          host,
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith(
        revert`createAuction listingFeePercentage plus findersFeePercentage must be less than 100`
      );
    });

    it('should revert if the funds recipient is 0', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;
      const hostAddress = await host.getAddress();
      const fundsRecipientAddress = ethers.constants.AddressZero;
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          0,
          zoraV1.address,
          duration,
          reservePrice,
          hostAddress,
          fundsRecipientAddress,
          listingFeePercentage,
          findersFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith(
        revert`createAuction fundsRecipient cannot be 0 address`
      );
    });

    it('should create an auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;
      const hostAddress = await host.getAddress();
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        hostAddress,
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency
      );

      const createdAuction = await reserveAuction.auctions(0);
      expect(createdAuction.duration.toNumber()).to.eq(duration);
      expect(createdAuction.reservePrice.toString()).to.eq(
        reservePrice.toString()
      );
      expect(createdAuction.listingFeePercentage).to.eq(listingFeePercentage);
      expect(createdAuction.host).to.eq(hostAddress);
      expect(createdAuction.fundsRecipient).to.eq(fundsRecipientAddress);
      expect(createdAuction.tokenOwner).to.eq(await deployer.getAddress());
      expect(createdAuction.findersFeePercentage).to.eq(findersFeePercentage);
    });

    xit('should emit an AuctionCreated event', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const listingFeePercentage = 10;
      const findersFeePercentage = 10;
      const hostAddress = await host.getAddress();
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const block = await ethers.provider.getBlockNumber();
      await reserveAuction.createAuction(
        0,
        zoraV1.address,
        duration,
        reservePrice,
        hostAddress,
        fundsRecipientAddress,
        listingFeePercentage,
        findersFeePercentage,
        auctionCurrency
      );

      const createdAuction = await reserveAuction.auctions(0);
      const events = await reserveAuction.queryFilter(
        new LibReserveAuctionV1Factory()
          .attach(reserveAuction.address)
          .filters.AuctionCreated(
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null
          ),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionCreated');
      expect(logDescription.args.auctionId.toNumber()).to.eq(0);
      expect(logDescription.args.tokenId.toNumber()).to.eq(
        createdAuction.tokenId.toNumber()
      );
      expect(logDescription.args.tokenContract).to.eq(
        createdAuction.tokenContract
      );
      expect(logDescription.args.duration.toNumber()).to.eq(
        createdAuction.duration.toNumber()
      );
      expect(logDescription.args.reservePrice.toString()).to.eq(
        createdAuction.reservePrice.toString()
      );
      expect(logDescription.args.host).to.eq(createdAuction.host);
      expect(logDescription.args.fundsRecipient).to.eq(
        createdAuction.fundsRecipient
      );
      expect(logDescription.args.listingFeePercentage).to.eq(
        createdAuction.listingFeePercentage
      );
      expect(logDescription.args.auctionCurrency).to.eq(
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
        await host.getAddress(),
        10,
        ethers.constants.AddressZero
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.setAuctionReservePrice(111, 1)
      ).eventually.rejectedWith();
    });

    it('should revert if the caller is not the owner or host', async () => {
      await expect(
        reserveAuction.connect(otherUser).setAuctionReservePrice(0, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice must be token owner`
      );
    });

    it('should revert if the auction has already started', async () => {
      await bid(reserveAuction, 0, ONE_ETH, await finder.getAddress());
      await expect(
        reserveAuction.setAuctionReservePrice(0, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice auction has already started`
      );
    });

    it('should set the reserve price for the auction', async () => {
      await reserveAuction.setAuctionReservePrice(0, ONE_ETH.mul(2));
      const auction = await reserveAuction.auctions(0);

      expect(auction.reservePrice.toString()).to.eq(ONE_ETH.mul(2).toString());
    });

    xit('should emit an AuctionReservePriceUpdated event', async () => {});
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
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 0, true);

      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(0, ONE_ETH.mul(2), await finder.getAddress())
      ).eventually.rejectedWith(revert`createBid auction expired`);
    });

    it('should revert if the bid does not meet the reserve price', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(0, 1, await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid must send at least reservePrice`
      );
    });

    it('should revert if the bid is not greater than 10% more of the previous bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(0, ONE_ETH.add(1), await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid must send more than the last bid by minBidIncrementPercentage amount`
      );
    });

    it('should revert if the _finder is zero address', async () => {
      await expect(
        reserveAuction
          .connect(bidderB)
          .createBid(0, ONE_ETH, ethers.constants.AddressZero)
      ).eventually.rejectedWith(
        revert`createBid _finder must not be 0 address`
      );
    });

    it('should revert if the bid is invalid on zora v1', async () => {
      await expect(
        reserveAuction
          .connect(bidderA)
          .createBid(0, ONE_ETH.add(1), await finder.getAddress())
      ).eventually.rejectedWith(
        revert`createBid bid invalid for share splitting`
      );
    });

    it('should set the starting time on the first bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      const auction = await reserveAuction.auctions(0);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
    });

    it('should refund the previous bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(
        await bidderA.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await bid(
        reserveAuction.connect(bidderB),
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
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const auction = await reserveAuction.auctions(0);

      expect(auction.firstBidTime.toNumber()).to.not.eq(0);
      expect(auction.amount.toString()).to.eq(ONE_ETH.toString());
      expect(auction.bidder).to.eq(await bidderA.getAddress());
      expect(
        (await ethers.provider.getBalance(reserveAuction.address)).toString()
      ).to.eq(ONE_ETH.toString());
    });

    it('should extend the auction if it is in its final moments', async () => {
      const oldDuration = (await reserveAuction.auctions(0)).duration;
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 0);
      await bid(
        reserveAuction.connect(bidderB),
        0,
        TWO_ETH,
        await finder.getAddress()
      );
      const newDuration = (await reserveAuction.auctions(0)).duration;

      expect(newDuration.toNumber()).to.eq(
        oldDuration.toNumber() - 1 + 15 * 60
      );
    });

    it('should take the NFT into escrow after the first bid', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      expect(await zoraV1.ownerOf(0)).to.eq(reserveAuction.address);
    });

    it('should set the current finder on the auction', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      const currFinder = (await reserveAuction.auctions(0)).finder;

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
          0,
          ONE_ETH,
          await finder.getAddress()
        )
      ).eventually.rejectedWith(
        revert`ERC721: transfer caller is not owner nor approved`
      );
    });

    xit('should emit an AuctionBid event', async () => {});

    xit('should emit an AuctionDurationExtended event', async () => {});
  });

  describe('#settleAuction', async () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        undefined
      );
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(reserveAuction.settleAuction(1111)).eventually.rejectedWith(
        revert`auctionExists auction doesn't exist`
      );
    });

    it('should revert if the auction has not begun', async () => {
      await mintZoraNFT(zoraV1, 'enw');
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address, '1');
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await deployer.getAddress(),
        ethers.constants.AddressZero,
        10,
        undefined,
        1
      );
      await expect(reserveAuction.settleAuction(1)).eventually.rejectedWith(
        revert`settleAuction auction hasn't begun`
      );
    });

    it('should revert if the auction has not completed', async () => {
      await mintZoraNFT(zoraV1, 'enwa');
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address, '1');
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await deployer.getAddress(),
        ethers.constants.AddressZero,
        10,
        undefined,
        1
      );
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );

      await expect(reserveAuction.settleAuction(1)).eventually.rejectedWith(
        revert`settleAuction auction hasn't completed`
      );
    });

    it('should handle a zora auction payout', async () => {
      await timeTravelToEndOfAuction(reserveAuction, 0, true);

      const beforeFundsRecipientBalance = await fundsRecipient.getBalance();
      const beforehostBalance = await host.getBalance();
      const beforeCreatorBalance = await deployer.getBalance();
      const beforeFinderBalance = await finder.getBalance();

      await settleAuction(reserveAuction, 0);

      const afterFundsRecipientBalance = await fundsRecipient.getBalance();
      const afterhostBalance = await host.getBalance();
      const afterCreatorBalance = await deployer.getBalance();
      const tokenOwner = await zoraV1.ownerOf(0);
      const afterFinderBalance = await finder.getBalance();

      expect(
        afterFundsRecipientBalance.sub(beforeFundsRecipientBalance).toString()
      ).to.eq('722500000000000000');
      expect(afterhostBalance.sub(beforehostBalance).toString()).to.eq(
        '42500000000000000'
      );
      expect(toRoundedNumber(afterCreatorBalance)).to.approximately(
        toRoundedNumber(beforeCreatorBalance),
        500
      );
      expect(afterFinderBalance.toString()).to.eq(
        beforeFinderBalance.add(THOUSANDTH_ETH.mul(85)).toString()
      );
      expect(tokenOwner).to.eq(await bidderA.getAddress());
    });

    it('should handle an eip2981 auction payout', async () => {
      await mintERC2981Token(testEIP2981ERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testEIP2981ERC721,
        erc721TransferHelper.address,
        '0'
      );
      await createReserveAuction(
        testEIP2981ERC721,
        reserveAuction,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        undefined,
        0
      );
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 1, true);

      const beforeFundsRecipientBalance = await fundsRecipient.getBalance();
      const beforeCreatorBalance = await deployer.getBalance();
      const beforehostBalance = await host.getBalance();
      const beforeFinderBalance = await finder.getBalance();
      await settleAuction(reserveAuction, 1);
      const afterFundsRecipientBalance = await fundsRecipient.getBalance();
      const afterCreatorBalance = await deployer.getBalance();
      const afterhostBalance = await host.getBalance();
      const afterFinderBalance = await finder.getBalance();

      const tokenOwner = await testEIP2981ERC721.ownerOf(0);

      expect(
        afterFundsRecipientBalance.sub(beforeFundsRecipientBalance).toString()
      ).to.eq('425000000000000000');
      expect(afterhostBalance.sub(beforehostBalance).toString()).to.eq(
        '25000000000000000'
      );
      expect(toRoundedNumber(afterCreatorBalance)).to.approximately(
        toRoundedNumber(beforeCreatorBalance.add(ONE_ETH.div(2))),
        500
      );
      expect(afterFinderBalance.toString()).to.eq(
        beforeFinderBalance.add(TENTH_ETH.div(2)).toString()
      );
      expect(tokenOwner).to.eq(await bidderA.getAddress());
    });

    it('should handle a vanilla erc721 auction payout', async () => {
      await mintERC721Token(testERC721, await deployer.getAddress());
      // @ts-ignore
      await approveNFTTransfer(testERC721, erc721TransferHelper.address);
      await createReserveAuction(
        testERC721,
        reserveAuction,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        undefined,
        0
      );
      await bid(
        reserveAuction.connect(bidderA),
        1,
        ONE_ETH,
        await finder.getAddress()
      );
      await timeTravelToEndOfAuction(reserveAuction, 1, true);

      await settleAuction(reserveAuction, 1);

      const fundsRecipientBalance = (
        await ethers.provider.getBalance(await fundsRecipient.getAddress())
      ).toString();
      const afterCreatorBalance = await ethers.provider.getBalance(
        await deployer.getAddress()
      );
      const hostBalance = await ethers.provider.getBalance(
        await host.getAddress()
      );
      const tokenOwner = await testERC721.ownerOf(0);

      expect(fundsRecipientBalance).to.eq('10000850000000000000000');
      expect(toRoundedNumber(hostBalance)).to.approximately(
        toRoundedNumber(BigNumber.from('10000050000000000000000')),
        2
      );
      expect(tokenOwner).to.eq(await bidderA.getAddress());
    });

    xit('should emit an AuctionEnded event', async () => {});
  });

  describe('#cancelAuction', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        undefined
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(reserveAuction.cancelAuction(1111)).eventually.rejectedWith(
        revert`auctionExists auction doesn't exist`
      );
    });

    it('should revert if not called by the host or creator before the first bid', async () => {
      await expect(
        reserveAuction.connect(otherUser).cancelAuction(0)
      ).eventually.rejectedWith(
        revert`cancelAuction only callable by auction creator`
      );
    });

    it('should revert if the auction has started', async () => {
      await bid(
        reserveAuction.connect(bidderA),
        0,
        ONE_ETH,
        await finder.getAddress()
      );

      await expect(reserveAuction.cancelAuction(0)).eventually.rejectedWith(
        revert`cancelAuction auction already started`
      );
    });

    it('should cancel an auction and return the token to the creator', async () => {
      await reserveAuction.cancelAuction(0);

      const deletedAuction = await reserveAuction.auctions(0);

      expect(await zoraV1.ownerOf(0)).to.eq(await deployer.getAddress());
      expect(deletedAuction.tokenContract).to.eq(ethers.constants.AddressZero);
      expect(deletedAuction.tokenOwner).to.eq(ethers.constants.AddressZero);
    });

    it('should allow anyone to cancel an auction if the token is no longer owned by the creator', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await bidderA.getAddress(),
        0
      );
      await reserveAuction.connect(otherUser).cancelAuction(0);

      const deletedAuction = await reserveAuction.auctions(0);
      expect(deletedAuction.tokenContract).to.eq(ethers.constants.AddressZero);
      expect(deletedAuction.tokenOwner).to.eq(ethers.constants.AddressZero);
    });

    xit('should emit an AuctionCanceled event', async () => {});
  });
});
