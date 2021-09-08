import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  ListingsV1,
  TestEip2981Erc721,
  TestErc721,
  Weth,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployListingsV1,
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
  TENTH_ETH,
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
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    fundsRecipient = signers[2];
    otherUser = signers[3];
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
      proposalManager.address,
      approvalManager.address
    );
    erc721TransferHelper = await deployERC721TransferHelper(
      proposalManager.address,
      approvalManager.address
    );
    listings = await deployListingsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      weth.address
    );

    await proposeModule(proposalManager, listings.address);
    await registerModule(proposalManager, listings.address);

    await approvalManager.setApprovalForAllModules(true);
    await approvalManager.connect(buyerA).setApprovalForAllModules(true);

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
        await fundsRecipient.getAddress()
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
        await fundsRecipient.getAddress()
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

    it('should revert if the funds recipient is the zero address', async () => {
      await expect(
        listings.createListing(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith('createListing must specify fundsRecipient');
    });
  });

  describe('#cancelListing', () => {
    beforeEach(async () => {
      await listings.createListing(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await fundsRecipient.getAddress()
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
      ).eventually.rejectedWith(revert`cancelListing must be seller`);
    });

    it('should revert if the listing has been filled already', async () => {
      await listings.connect(buyerA).fillListing(1, { value: ONE_ETH });

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
        await fundsRecipient.getAddress()
      );
    });

    it('should fill a listing', async () => {
      const buyerBeforeBalance = await buyerA.getBalance();
      const minterBeforeBalance = await deployer.getBalance();
      const fundsRecipientBeforeBalance = await fundsRecipient.getBalance();
      await listings.connect(buyerA).fillListing(1, { value: ONE_ETH });
      const buyerAfterBalance = await buyerA.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const fundsRecipientAfterBalance = await fundsRecipient.getBalance();

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
      // 15% creator fee + 1 ETH bid -> .85 ETH profit
      expect(toRoundedNumber(fundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          fundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(850))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
    });
  });
});
