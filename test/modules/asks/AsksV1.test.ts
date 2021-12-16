import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  AsksV1,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployAsksV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintZoraNFT,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
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
  let weth: WETH;
  let deployer: Signer;
  let buyerA: Signer;
  let sellerFundsRecipient: Signer;
  let finder: Signer;
  let otherUser: Signer;
  let operator: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    sellerFundsRecipient = signers[2];
    otherUser = signers[3];
    finder = signers[4];
    operator = signers[5];
    const zoraV1Protocol = await deployZoraProtocol();
    zoraV1 = zoraV1Protocol.media;
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
    it('should create an ask from a token owner', async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        10
      );

      const ask = await asks.askForNFT(zoraV1.address, 0);

      expect(ask.seller).to.eq(await deployer.getAddress());
      expect(ask.sellerFundsRecipient).to.eq(
        await sellerFundsRecipient.getAddress()
      );
      expect(ask.askCurrency).to.eq(ethers.constants.AddressZero);
      expect(ask.askPrice.toString()).to.eq(ONE_ETH.toString());
    });

    it('should create an ask from an approved operator', async () => {
      await zoraV1.connect(deployer).approve(await operator.getAddress(), 0);

      await asks
        .connect(operator)
        .createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          10
        );

      const ask = await asks.askForNFT(zoraV1.address, 0);

      expect(ask.seller).to.eq(await deployer.getAddress());
    });

    it('should cancel an ask created by previous owner', async () => {
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        10
      );

      const beforeAskSeller = (await asks.askForNFT(zoraV1.address, 0)).seller;
      expect(beforeAskSeller).to.eq(await deployer.getAddress());

      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await buyerA.getAddress(),
        0
      );

      await asks
        .connect(buyerA)
        .createAsk(
          zoraV1.address,
          0,
          TWO_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          10
        );

      const afterAskSeller = (await asks.askForNFT(zoraV1.address, 0)).seller;
      expect(afterAskSeller).to.eq(await buyerA.getAddress());
    });

    it('should emit an AskCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await asks.createAsk(
        zoraV1.address,
        0,
        ONE_ETH,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress(),
        10
      );

      const events = await asks.queryFilter(
        asks.filters.AskCreated(null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskCreated');
      expect(logDescription.args.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.tokenContract).to.eq(zoraV1.address);
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
            10
          )
      ).eventually.rejectedWith(
        'createAsk must be token owner or approved operator'
      );
    });

    it('should revert if the funds recipient is the zero address', async () => {
      await expect(
        asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          10
        )
      ).eventually.rejectedWith('createAsk must specify sellerFundsRecipient');
    });

    it('should revert if the finders fee percentage is greater than 100', async () => {
      await expect(
        asks.createAsk(
          zoraV1.address,
          0,
          ONE_ETH,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress(),
          101
        )
      ).eventually.rejectedWith(
        'createAsk finders fee percentage must be less than or equal to 100'
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
        10
      );
    });

    it('should update the ask price', async () => {
      await asks.setAskPrice(zoraV1.address, 0, TWO_ETH, weth.address);

      const ask = await asks.askForNFT(zoraV1.address, 0);

      expect(ask.askPrice.toString()).to.eq(TWO_ETH.toString());
      expect(ask.askCurrency).to.eq(weth.address);
    });

    it('should emit an AskPriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks.setAskPrice(zoraV1.address, 0, TWO_ETH, weth.address);

      const events = await asks.queryFilter(
        asks.filters.AskPriceUpdated(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskPriceUpdated');
      expect(logDescription.args.ask.askCurrency).to.eq(weth.address);
    });

    it('should revert when the msg.sender is not the seller', async () => {
      await expect(
        asks
          .connect(buyerA)
          .setAskPrice(zoraV1.address, 0, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setAskPrice must be seller`);
    });
    it('should revert if the ask has been sold', async () => {
      await asks
        .connect(buyerA)
        .fillAsk(zoraV1.address, 0, await finder.getAddress(), {
          value: ONE_ETH,
        });

      await expect(
        asks.setAskPrice(zoraV1.address, 0, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setAskPrice must be seller`);
    });
    it('should revert if the ask has been canceled', async () => {
      await asks.cancelAsk(zoraV1.address, 0);

      await expect(
        asks.setAskPrice(zoraV1.address, 0, TWO_ETH, weth.address)
      ).eventually.rejectedWith(revert`setAskPrice must be seller`);
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
        10
      );
    });

    it('should cancel an ask', async () => {
      await asks.cancelAsk(zoraV1.address, 0);
      const ask = await asks.askForNFT(zoraV1.address, 0);
      expect(ask.seller.toString()).to.eq(
        ethers.constants.AddressZero.toString()
      );

      const askForNFT = await asks.askForNFT(zoraV1.address, 0);
      expect(askForNFT.seller.toString()).to.eq(ethers.constants.AddressZero);
    });

    it('should emit an AskCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks.cancelAsk(zoraV1.address, 0);

      const events = await asks.queryFilter(
        asks.filters.AskCanceled(null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('AskCanceled');
      expect(logDescription.args.ask.seller).to.eq(await deployer.getAddress());
    });

    it('should revert when the seller is not msg.sender', async () => {
      await expect(
        asks.connect(otherUser).cancelAsk(zoraV1.address, 0)
      ).eventually.rejectedWith(
        revert`cancelAsk must be seller or invalid ask`
      );
    });

    it('should cancel an ask if the ask is no longer valid', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await buyerA.getAddress(),
        0
      );
      await asks.connect(buyerA).cancelAsk(zoraV1.address, 0);
      const ask = await asks.askForNFT(zoraV1.address, 0);
      expect(ask.seller.toString()).to.eq(
        ethers.constants.AddressZero.toString()
      );
    });

    it('should revert if the ask has been filled already', async () => {
      await asks
        .connect(buyerA)
        .fillAsk(zoraV1.address, 0, await finder.getAddress(), {
          value: ONE_ETH,
        });

      await expect(asks.cancelAsk(zoraV1.address, 0)).rejectedWith(
        revert`cancelAsk must be seller or invalid ask`
      );
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
      const finderBeforeBalance = await finder.getBalance();
      await asks
        .connect(buyerA)
        .fillAsk(zoraV1.address, 0, await finder.getAddress(), {
          value: ONE_ETH,
        });
      const buyerAfterBalance = await buyerA.getBalance();
      const minterAfterBalance = await deployer.getBalance();
      const sellerFundsRecipientAfterBalance =
        await sellerFundsRecipient.getBalance();
      const finderAfterBalance = await finder.getBalance();

      const ask = await asks.askForNFT(zoraV1.address, 0);
      expect(ask.seller.toString()).to.eq(ethers.constants.AddressZero);

      expect(toRoundedNumber(buyerAfterBalance)).to.approximately(
        toRoundedNumber(buyerBeforeBalance.sub(ONE_ETH)),
        5
      );
      // 0.5ETH royalty fee
      expect(toRoundedNumber(minterAfterBalance)).to.eq(
        toRoundedNumber(minterBeforeBalance.add(ONE_ETH.div(2)))
      );

      // 0.5ETH creator fee + 1 ETH bid * 10% finder fee -> .05 ETH profit
      expect(toRoundedNumber(finderAfterBalance)).to.eq(
        toRoundedNumber(finderBeforeBalance.add(THOUSANDTH_ETH.mul(50)))
      );

      // ask fee - creator fee - finder fee -> .765 ETH profit
      expect(toRoundedNumber(sellerFundsRecipientAfterBalance)).to.eq(
        toRoundedNumber(
          sellerFundsRecipientBeforeBalance.add(THOUSANDTH_ETH.mul(450))
        )
      );

      expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
    });

    it('should emit an ExchangeExecuted event', async () => {
      const block = await ethers.provider.getBlockNumber();

      await asks
        .connect(buyerA)
        .fillAsk(zoraV1.address, 0, await finder.getAddress(), {
          value: ONE_ETH,
        });

      const events = await asks.queryFilter(
        asks.filters.ExchangeExecuted(null, null, null, null),
        block
      );

      expect(events.length).to.eq(1);

      const logDescription = asks.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('ExchangeExecuted');
      expect(logDescription.args.userA).to.eq(await deployer.getAddress());
      expect(logDescription.args.userB).to.eq(await buyerA.getAddress());

      expect(logDescription.args.a.tokenContract).to.eq(zoraV1.address);
      expect(logDescription.args.b.tokenContract).to.eq(
        ethers.constants.AddressZero
      );
    });
  });
});
