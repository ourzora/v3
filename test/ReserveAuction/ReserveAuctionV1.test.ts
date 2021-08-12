import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  BadErc721,
  LibReserveAuctionV1Factory,
  ReserveAuctionProxy,
  ReserveAuctionV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
} from '../../typechain';
import {
  approveNFTTransfer,
  bid,
  connectAs,
  createReserveAuction,
  deployBadERC721,
  deployReserveAuctionProxy,
  deployReserveAuctionV1,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployWETH,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_ETH,
  registerVersion,
  revert,
} from '../utils';
import { BigNumber, Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';

chai.use(asPromised);

describe('ReserveAuctionV1', () => {
  let proxy: ReserveAuctionProxy;
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let badERC721: BadErc721;
  let testERC721: TestErc721;
  let testEIP2981ERC721: TestEip2981Erc721;
  let weth: Weth;
  let deployer: Signer;
  let curator: Signer;
  let bidderA: Signer;
  let bidderB: Signer;
  let fundsRecipient: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    await ethers.provider.send('hardhat_reset', []);
    proxy = await deployReserveAuctionProxy();
    const module = await deployReserveAuctionV1();
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    badERC721 = await deployBadERC721();
    testERC721 = await deployTestERC271();
    testEIP2981ERC721 = await deployTestEIP2981ERC721();
    weth = await deployWETH();
    const signers = await ethers.getSigners();
    deployer = signers[0];
    curator = signers[1];
    bidderA = signers[2];
    bidderB = signers[3];
    fundsRecipient = signers[4];
    otherUser = signers[5];
    const initCallData = module.interface.encodeFunctionData('initialize', [
      zoraV1.address,
      weth.address,
    ]);
    await registerVersion(proxy, module.address, initCallData);
    reserveAuction = await connectAs<ReserveAuctionV1>(
      proxy,
      'ReserveAuctionV1'
    );
  });

  describe('#createAuction', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, reserveAuction.address);
    });

    it('should revert if the 721 token does not support the ERC721 interface', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);

      await expect(
        reserveAuction.createAuction(
          1,
          0,
          badERC721.address,
          duration,
          reservePrice,
          await curator.getAddress(),
          await fundsRecipient.getAddress(),
          5,
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith(
        revert`createAuction tokenContract does not support ERC721 interface`
      );
    });

    it('should revert if the token owner has not approved an auction', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 15;
      const curator = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction
          .connect(otherUser)
          .createAuction(
            1,
            0,
            zoraV1.address,
            duration,
            reservePrice,
            curator,
            fundsRecipientAddress,
            curatorFeePercentage,
            auctionCurrency
          )
      ).eventually.rejectedWith(
        revert`createAuction caller must be approved or owner for token id`
      );
    });

    it('should revert if the token ID does not exist', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 15;
      const curator = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          1,
          888,
          zoraV1.address,
          duration,
          reservePrice,
          curator,
          fundsRecipientAddress,
          curatorFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith('ERC721: approved query for nonexistent token');
    });

    it('should revert if the curator fee percentage is >= 100', async () => {
      const duration = 60 * 68 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 100;
      const curator = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          1,
          0,
          zoraV1.address,
          duration,
          reservePrice,
          curator,
          fundsRecipientAddress,
          curatorFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith(
        revert`createAuction curatorFeePercentage must be less than 100`
      );
    });

    it('should revert if the funds recipient is 0', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 10;
      const curatorAddress = await curator.getAddress();
      const fundsRecipientAddress = ethers.constants.AddressZero;
      const auctionCurrency = ethers.constants.AddressZero;

      await expect(
        reserveAuction.createAuction(
          1,
          0,
          zoraV1.address,
          duration,
          reservePrice,
          curatorAddress,
          fundsRecipientAddress,
          curatorFeePercentage,
          auctionCurrency
        )
      ).eventually.rejectedWith(
        revert`createAuction fundsRecipient cannot be 0 address`
      );
    });

    it('should create an auction', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 10;
      const curatorAddress = await curator.getAddress();
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        1,
        0,
        zoraV1.address,
        duration,
        reservePrice,
        curatorAddress,
        fundsRecipientAddress,
        curatorFeePercentage,
        auctionCurrency
      );

      const createdAuction = await reserveAuction.auctions(1, 0);
      expect(createdAuction.duration.toNumber()).to.eq(duration);
      expect(createdAuction.reservePrice.toString()).to.eq(
        reservePrice.toString()
      );
      expect(createdAuction.curatorFeePercentage).to.eq(curatorFeePercentage);
      expect(createdAuction.curator).to.eq(curatorAddress);
      expect(createdAuction.fundsRecipient).to.eq(fundsRecipientAddress);
      expect(createdAuction.tokenOwner).to.eq(await deployer.getAddress());
      expect(createdAuction.approved).to.eq(false);
    });

    it('should be automatically approved if the auction creator is the curator', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 10;
      const curatorAddress = await deployer.getAddress();
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        1,
        0,
        zoraV1.address,
        duration,
        reservePrice,
        curatorAddress,
        fundsRecipientAddress,
        curatorFeePercentage,
        auctionCurrency
      );
      const createdAuction = await reserveAuction.auctions(1, 0);

      expect(createdAuction.approved).to.eq(true);
    });

    it('should be automatically approved if the curator is 0x0', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 10;
      const curatorAddress = ethers.constants.AddressZero;
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      await reserveAuction.createAuction(
        1,
        0,
        zoraV1.address,
        duration,
        reservePrice,
        curatorAddress,
        fundsRecipientAddress,
        curatorFeePercentage,
        auctionCurrency
      );
      const createdAuction = await reserveAuction.auctions(1, 0);

      expect(createdAuction.approved).to.eq(true);
    });

    // For some reason this event fires but isn't parsable..
    // TODO debug why
    xit('should emit an AuctionCreated event', async () => {
      const duration = 60 * 60 * 24;
      const reservePrice = BigNumber.from(10).pow(18).div(2);
      const curatorFeePercentage = 10;
      const curatorAddress = await curator.getAddress();
      const fundsRecipientAddress = await fundsRecipient.getAddress();
      const auctionCurrency = ethers.constants.AddressZero;

      const block = await ethers.provider.getBlockNumber();
      const tx = await reserveAuction.createAuction(
        1,
        0,
        zoraV1.address,
        duration,
        reservePrice,
        curatorAddress,
        fundsRecipientAddress,
        curatorFeePercentage,
        auctionCurrency
      );

      const createdAuction = await reserveAuction.auctions(1, 0);
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
      expect(logDescription.args.curator).to.eq(createdAuction.curator);
      expect(logDescription.args.fundsRecipient).to.eq(
        createdAuction.fundsRecipient
      );
      expect(logDescription.args.curatorFeePercentage).to.eq(
        createdAuction.curatorFeePercentage
      );
      expect(logDescription.args.auctionCurrency).to.eq(
        ethers.constants.AddressZero
      );
    });
  });

  describe('#setAuctionApproval', async () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, reserveAuction.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await deployer.getAddress(),
        await curator.getAddress()
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.setAuctionApproval(1, 11, true)
      ).eventually.rejectedWith(revert`auctionExists auction doesn't exist`);
    });

    it('should revert if not called by the curator', async () => {
      await expect(
        reserveAuction.connect(otherUser).setAuctionApproval(1, 0, true)
      ).eventually.rejectedWith(
        revert`setAuctionApproval must be auction curator`
      );
    });

    it('should revert if the auction has already started', async () => {
      await reserveAuction.connect(curator).setAuctionApproval(1, 0, true);
      await bid(reserveAuction, 0, ONE_ETH);

      await expect(
        reserveAuction.connect(curator).setAuctionApproval(1, 0, false)
      ).eventually.rejectedWith(
        'setAuctionApproval auction has already started'
      );
    });

    it('should approve the auction', async () => {
      await reserveAuction.connect(curator).setAuctionApproval(1, 0, true);
      const auction = await reserveAuction.auctions(1, 0);

      expect(auction.approved).to.eq(true);
    });

    xit('should emit an AuctionApprovalUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await reserveAuction.connect(curator).setAuctionApproval(1, 0, true);

      const events = await reserveAuction.queryFilter(
        new LibReserveAuctionV1Factory()
          .attach(reserveAuction.address)
          .filters.AuctionApprovalUpdated(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = reserveAuction.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AuctionApprovalUpdated');
    });
  });

  describe('#setAuctionReservePrice', () => {
    beforeEach(async () => {
      await mintZoraNFT(zoraV1);
      await approveNFTTransfer(zoraV1, reserveAuction.address);
      await createReserveAuction(
        zoraV1,
        reserveAuction,
        await deployer.getAddress(),
        ethers.constants.AddressZero
      );
    });

    it('should revert if the auction does not exist', async () => {
      await expect(
        reserveAuction.setAuctionReservePrice(1, 111, 1)
      ).eventually.rejectedWith();
    });

    it('should revert if the caller is not the owner or curator', async () => {
      await expect(
        reserveAuction.connect(otherUser).setAuctionReservePrice(1, 0, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice must be auction curator or token owner`
      );
    });

    it('should revert if the auction has already started', async () => {
      await bid(reserveAuction, 0, ONE_ETH);
      await expect(
        reserveAuction.setAuctionReservePrice(1, 0, 1)
      ).eventually.rejectedWith(
        revert`setAuctionReservePrice auction has already started`
      );
    });

    it('should set the reserve price for the auction', async () => {
      await reserveAuction.setAuctionReservePrice(1, 0, ONE_ETH.mul(2));
      const auction = await reserveAuction.auctions(1, 0);

      expect(auction.reservePrice.toString()).to.eq(ONE_ETH.mul(2).toString());
    });

    xit('should emit an AuctionReservePriceUpdated event', async () => {});
  });
});
