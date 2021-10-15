import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  ListingsV1,
  RoyaltyRegistryV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployListingsV1,
  deployRoyaltyRegistry,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
  THOUSANDTH_ETH,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';
chai.use(asPromised);

describe('ListingsV1', () => {
  let listings: ListingsV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let testEIP2981ERC721: TestEip2981Erc721;
  let weth: Weth;
  let deployer: Signer;
  let buyerA: Signer;
  let fundsRecipient: Signer;
  let host: Signer;
  let finder: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;
  let royaltyRegistry: RoyaltyRegistryV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    fundsRecipient = signers[2];
    host = signers[3];
    otherUser = signers[4];
    finder = signers[5];
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
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
    royaltyRegistry = await deployRoyaltyRegistry();
    listings = await deployListingsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      royaltyRegistry.address,
      weth.address
    );

    await proposeModule(proposalManager, listings.address);
    await registerModule(proposalManager, listings.address);

    await approvalManager.setApprovalForModule(listings.address, true);
    await approvalManager
      .connect(buyerA)
      .setApprovalForModule(listings.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createListing', () => {
    it('should create a listing', async () => {
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        10
      );

      const listing = await listings.listings(1);

      expect(listing.tokenContract).to.eq(zoraV1.address);
      expect(listing.seller).to.eq(await deployer.getAddress());
      expect(listing.fundsRecipient).to.eq(await fundsRecipient.getAddress());
      expect(listing.listingCurrency).to.eq(ethers.constants.AddressZero);
      expect(listing.tokenId.toNumber()).to.eq(0);
      expect(listing.listingPrice.toString()).to.eq(ONE_ETH.toString());
      expect(listing.status).to.eq(0);

      expect(
        (
          await listings.listingsForUser(await deployer.getAddress(), 0)
        ).toNumber()
      ).to.eq(1);
      expect(
        (await listings.listingForNFT(zoraV1.address, 0)).toNumber()
      ).to.eq(1);
    });

    it('should emit a ListingCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        10
      );

      const events = await listings.queryFilter(
        listings.filters.ListingCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = listings.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ListingCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.listing.seller).to.eq(
        await deployer.getAddress()
      );
    });

    it('should revert if seller is not token owner', async () => {
      await expect(
        listings
          .connect(otherUser)
          .createListing(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            await host.getAddress(),
            10,
            10
          )
      ).eventually.rejectedWith('createListing must be token owner');
    });

    it('should revert if the funds recipient is the zero address', async () => {
      await expect(
        listings.createListing(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          await host.getAddress(),
          10,
          10
        )
      ).eventually.rejectedWith('createListing must specify fundsRecipient');
    });

    it('should revert if the lising fee percentage is greater than 100', async () => {
      await expect(
        listings.createListing(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await fundsRecipient.getAddress(),
          await host.getAddress(),
          101,
          10
        )
      ).eventually.rejectedWith(
        'createListing listing fee and finders fee percentage must be less than 100'
      );
    });
  });

  describe('#setListingPrice', () => {
    beforeEach(async () => {
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        10
      );
    });

    it('should update the listing price', async () => {
      await listings.setListingPrice(1, TWO_ETH, weth.address);

      const listing = await listings.listings(1);

      expect(listing.listingPrice.toString()).to.eq(TWO_ETH.toString());
      expect(listing.listingCurrency).to.eq(weth.address);
    });

    it('should emit a ListingPriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await listings.setListingPrice(1, TWO_ETH, weth.address);

      const events = await listings.queryFilter(
        listings.filters.ListingPriceUpdated(null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = listings.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ListingPriceUpdated');
      expect(logDescription.args.listing.listingCurrency).to.eq(weth.address);
    });

    it('should revert when the msg.sender is not the seller', async () => {
      await expect(
        listings.connect(host).setListingPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setListingPrice must be seller`);
    });
    it('should revert if the listing has been sold', async () => {
      await listings
        .connect(buyerA)
        .fillListing(1, await finder.getAddress(), { value: ONE_ETH });

      await expect(
        listings.setListingPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setListingPrice must be active listing`);
    });
    it('should revert if the listing has been canceled', async () => {
      await listings.cancelListing(1);

      await expect(
        listings.setListingPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setListingPrice must be active listing`);
    });
  });

  describe('#cancelListing', () => {
    beforeEach(async () => {
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        10
      );
    });

    it('should cancel a listing', async () => {
      await listings.cancelListing(1);
      const listing = await listings.listings(1);
      expect(listing.status).to.eq(1);
    });

    it('should emit a ListingCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await listings.cancelListing(1);

      const events = await listings.queryFilter(
        listings.filters.ListingCanceled(null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = listings.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ListingCanceled');
      expect(logDescription.args.listing.seller).to.eq(
        await deployer.getAddress()
      );
    });

    it('should revert when the seller is not msg.sender', async () => {
      await expect(
        listings.connect(otherUser).cancelListing(1)
      ).eventually.rejectedWith(
        revert`cancelListing must be seller or invalid listing`
      );
    });

    it('should cancel a listing if the listing is no longer valid', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await buyerA.getAddress(),
        0
      );
      await listings.connect(otherUser).cancelListing(1);
      const listing = await listings.listings(1);
      expect(listing.status).to.eq(1);
    });

    it('should revert if the listing has been filled already', async () => {
      await listings
        .connect(buyerA)
        .fillListing(1, await finder.getAddress(), { value: ONE_ETH });

      await expect(listings.cancelListing(1)).rejectedWith(
        revert`cancelListing must be active listing`
      );
    });
  });

  describe('#fillListing', () => {
    beforeEach(async () => {
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress(),
        await host.getAddress(),
        10,
        10
      );
    });

    it('should fill a listing', async () => {
      const buyerBeforeBalance = await buyerA.getBalance();
      const minterBeforeBalance = await deployer.getBalance();
      const fundsRecipientBeforeBalance = await fundsRecipient.getBalance();
      const hostBeforeBalance = await host.getBalance();
      const finderBeforeBalance = await finder.getBalance();
      await listings
        .connect(buyerA)
        .fillListing(1, await finder.getAddress(), { value: ONE_ETH });
      const buyerAfterBalance = await buyerA.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const fundsRecipientAfterBalance = await fundsRecipient.getBalance();
      const hostAfterBalance = await host.getBalance();
      const finderAfterBalance = await finder.getBalance();

      const listing = await listings.listings(1);

      expect(listing.status).to.eq(2);

      expect(toRoundedNumber(buyerAfterBalance)).to.approximately(
        toRoundedNumber(buyerBeforeBalance.sub(ONE_ETH)),
        5
      );
      // 15% creator fee + 1 ETH bid -> .15 ETH profit
      expect(toRoundedNumber(minterAfterBalance)).to.eq(
        toRoundedNumber(minterBeforeBalance.add(THOUSANDTH_ETH.mul(150)))
      );
      // 15% creator fee + 1 ETH bid * 10% listing fee -> .085 ETH profit
      expect(toRoundedNumber(hostAfterBalance)).to.eq(
        toRoundedNumber(hostBeforeBalance.add(THOUSANDTH_ETH.mul(85)))
      );

      // 15% creator fee + 1 ETH bid * 10% finder fee -> .085 ETH profit
      expect(toRoundedNumber(finderAfterBalance)).to.eq(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(85)))
      );

      // listing fee - creator fee - finder fee -> .68 ETH profit
      expect(toRoundedNumber(fundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          fundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(680))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
    });
  });
});
