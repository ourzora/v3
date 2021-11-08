import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  AsksV1,
  TestEIP2981ERC721,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployAsksV1,
  deployRoyaltyEngine,
  deployTestEIP2981ERC721,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  THOUSANDTH_ETH,
  toRoundedNumber,
  TWO_ETH,
  deployZoraProtocol,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('AsksV1', () => {
  let asks: AsksV1;
  let zoraV1: Media;
  let testERC721: TestERC721;
  let testEIP2981ERC721: TestEIP2981ERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyerA: Signer;
  let sellerFundsRecipient: Signer;
  let listingFeeRecipient: Signer;
  let finder: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    sellerFundsRecipient = signers[2];
    listingFeeRecipient = signers[3];
    otherUser = signers[4];
    finder = signers[5];
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
    asks = await deployAsksV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      weth.address
    );

    await proposeModule(proposalManager, asks.address);
    await registerModule(proposalManager, asks.address);

    await approvalManager.setApprovalForModule(asks.address, true);
    await approvalManager
      .connect(buyerA)
      .setApprovalForModule(asks.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createAsk', () => {
    it('should create an ask', async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        await listingFeeRecipient.getAddress(),
        10,
        10
      );

      const ask = await asks.asks(1);

      expect(ask.tokenContract).to.eq(zoraV1.address);
      expect(ask.seller).to.eq(await deployer.getAddress());
      expect(ask.sellerFundsRecipient).to.eq(
        await sellerFundsRecipient.getAddress()
      );
      expect(ask.askCurrency).to.eq(ethers.constants.AddressZero);
      expect(ask.tokenId.toNumber()).to.eq(0);
      expect(ask.askPrice.toString()).to.eq(ONE_ETH.toString());
      expect(ask.status).to.eq(0);

      expect(
        (await asks.asksForUser(await deployer.getAddress(), 0)).toNumber()
      ).to.eq(1);
      expect((await asks.askForNFT(zoraV1.address, 0)).toNumber()).to.eq(1);
    });

    it('should emit an AskCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        await listingFeeRecipient.getAddress(),
        10,
        10
      );

      const events = await asks.queryFilter(
        asks.filters.AskCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.ask.seller).to.eq(await deployer.getAddress());
    });

    it('should revert if seller is not token owner', async () => {
      await expect(
        asks
          .connect(otherUser)
          .createAsk(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            await listingFeeRecipient.getAddress(),
            10,
            10
          )
      ).eventually.rejectedWith('CreateAskOnlyTokenOwnerOrOperator()');

      // .eventually.rejectedWith(
      //   await asks.interface.functions['CreateAskOnlyTokenOwnerOrOperator']
      // );
    });

    it('should revert if the funds recipient is the zero address', async () => {
      await expect(
        asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          await listingFeeRecipient.getAddress(),
          10,
          10
        )
      ).eventually.rejectedWith('CreateAskSpecifySellerFundsRecipient()');
    });

    it('should revert if the lising fee percentage is greater than 100', async () => {
      await expect(
        asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          await listingFeeRecipient.getAddress(),
          101,
          10
        )
      ).eventually.rejectedWith(
        'CreateAskListingAndFindersFeeCannotExceed100()'
      );
    });
  });

  describe('#setAskPrice', () => {
    beforeEach(async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        await listingFeeRecipient.getAddress(),
        10,
        10
      );
    });

    it('should update the ask price', async () => {
      await asks.setAskPrice(1, TWO_ETH, weth.address);

      const ask = await asks.asks(1);

      expect(ask.askPrice.toString()).to.eq(TWO_ETH.toString());
      expect(ask.askCurrency).to.eq(weth.address);
    });

    it('should emit an AskPriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks.setAskPrice(1, TWO_ETH, weth.address);

      const events = await asks.queryFilter(
        asks.filters.AskPriceUpdated(null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskPriceUpdated');
      expect(logDescription.args.ask.askCurrency).to.eq(weth.address);
    });

    it('should revert when the msg.sender is not the seller', async () => {
      await expect(
        asks.connect(listingFeeRecipient).setAskPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith('SetAskPriceOnlySeller()');
    });

    it('should revert if the ask has been sold', async () => {
      await asks
        .connect(buyerA)
        .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });

      await expect(
        asks.setAskPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith('SetAskPriceOnlyActiveAsk()');
    });
    it('should revert if the ask has been canceled', async () => {
      await asks.cancelAsk(1);

      await expect(
        asks.setAskPrice(1, TWO_ETH, weth.address)
      ).eventually.rejectedWith('SetAskPriceOnlyActiveAsk()');
    });
  });

  describe('#cancelAsk', () => {
    beforeEach(async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        await listingFeeRecipient.getAddress(),
        10,
        10
      );
    });

    it('should cancel an ask', async () => {
      await asks.cancelAsk(1);
      const ask = await asks.asks(1);
      expect(ask.status).to.eq(1);
    });

    it('should emit an AskCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks.cancelAsk(1);

      const events = await asks.queryFilter(
        asks.filters.AskCanceled(null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskCanceled');
      expect(logDescription.args.ask.seller).to.eq(await deployer.getAddress());
    });

    it('should revert when the seller is not msg.sender', async () => {
      await expect(
        asks.connect(otherUser).cancelAsk(1)
      ).eventually.rejectedWith('CancelAskOnlySellerOrInvalidAsk()');
    });

    it('should cancel an ask if the ask is no longer valid', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await buyerA.getAddress(),
        0
      );
      await asks.connect(otherUser).cancelAsk(1);
      const ask = await asks.asks(1);
      expect(ask.status).to.eq(1);
    });

    it('should revert if the ask has been filled already', async () => {
      await asks
        .connect(buyerA)
        .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });

      await expect(asks.cancelAsk(1)).rejectedWith('CancelAskOnlyActiveAsk()');
    });
  });

  describe('#fillAsk', () => {
    beforeEach(async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        await listingFeeRecipient.getAddress(),
        10,
        10
      );
    });

    it('should fill an ask', async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [ONE_ETH.div(2)]
      );

      const buyerBeforeBalance = await buyerA.getBalance();
      const minterBeforeBalance = await deployer.getBalance();
      const sellerFundsRecipientBeforeBalance =
        await sellerFundsRecipient.getBalance();
      const listingFeeRecipientBeforeBalance =
        await listingFeeRecipient.getBalance();
      const finderBeforeBalance = await finder.getBalance();
      await asks
        .connect(buyerA)
        .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });
      const buyerAfterBalance = await buyerA.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const sellerFundsRecipientAfterBalance =
        await sellerFundsRecipient.getBalance();
      const listingFeeRecipientAfterBalance =
        await listingFeeRecipient.getBalance();
      const finderAfterBalance = await finder.getBalance();

      const ask = await asks.asks(1);

      expect(ask.status).to.eq(2);

      expect(toRoundedNumber(buyerAfterBalance)).to.approximately(
        toRoundedNumber(buyerBeforeBalance.sub(ONE_ETH)),
        5
      );
      // 0.5ETH royalty fee
      expect(toRoundedNumber(minterAfterBalance)).to.eq(
        toRoundedNumber(minterBeforeBalance.add(ONE_ETH.div(2)))
      );
      // 0.5ETH creator fee + 1 ETH bid * 10% ask fee -> .05 ETH profit
      expect(toRoundedNumber(listingFeeRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          listingFeeRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(50))
        )
      );

      // 0.5ETH creator fee + 1 ETH bid * 10% finder fee -> .05 ETH profit
      expect(toRoundedNumber(finderAfterBalance)).to.eq(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(50)))
      );

      // ask fee - creator fee - finder fee -> .68 ETH profit
      expect(toRoundedNumber(sellerFundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          sellerFundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(400))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
    });

    it('should emit an ExchangeExecuted event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks
        .connect(buyerA)
        .fillAsk(1, await finder.getAddress(), { value: ONE_ETH });

      const events = await asks.queryFilter(
        asks.filters.ExchangeExecuted(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ExchangeExecuted');
      expect(logDescription.args.userA).to.eq(await deployer.getAddress());
      expect(logDescription.args.userB).to.eq(await buyerA.getAddress());

      expect(logDescription.args.a.tokenContract).to.eq(
        await (
          await asks.asks(1)
        ).tokenContract
      );
      expect(logDescription.args.b.tokenContract).to.eq(
        ethers.constants.AddressZero
      );
    });
  });
});
