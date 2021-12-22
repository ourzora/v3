import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredCallsV1,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCoveredCallsV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintZoraNFT,
  ONE_HALF_ETH,
  ONE_ETH,
  proposeModule,
  registerModule,
  deployZoraProtocol,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);

describe('CoveredCallsV1', () => {
  let calls: CoveredCallsV1;
  let zoraV1: Media;
  let weth: WETH;
  let deployer: Signer;
  let buyer: Signer;
  let sellerFundsRecipient: Signer;
  let otherUser: Signer;
  let operator: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    sellerFundsRecipient = signers[2];
    otherUser = signers[3];
    operator = signers[4];

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
    calls = await deployCoveredCallsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      weth.address
    );

    await proposeModule(proposalManager, calls.address);
    await registerModule(proposalManager, calls.address);

    await approvalManager.setApprovalForModule(calls.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(calls.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createCall', () => {
    it('should create a call option from a token owner', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST),
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      const call = await calls.callForNFT(zoraV1.address, 0);

      expect(call.seller).to.eq(await deployer.getAddress());
      expect(call.sellerFundsRecipient).to.eq(
        await sellerFundsRecipient.getAddress()
      );
      expect(call.buyer).to.eq(ethers.constants.AddressZero);
      expect(call.currency).to.eq(ethers.constants.AddressZero);
      expect(call.premium.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(call.strike.toString()).to.eq(ONE_ETH.toString());
      expect(call.expiration.toNumber()).to.eq(2238366608);
    });

    it('should create a call option from a token operator', async () => {
      await zoraV1
        .connect(deployer)
        .setApprovalForAll(await operator.getAddress(), true);

      await calls.connect(operator).createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      const call = await calls.callForNFT(zoraV1.address, 0);

      expect(call.seller).to.eq(await deployer.getAddress());
      expect(call.sellerFundsRecipient).to.eq(
        await sellerFundsRecipient.getAddress()
      );
      expect(call.buyer).to.eq(ethers.constants.AddressZero);
      expect(call.currency).to.eq(ethers.constants.AddressZero);
      expect(call.premium.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(call.strike.toString()).to.eq(ONE_ETH.toString());
      expect(call.expiration.toNumber()).to.eq(2238366608);
    });

    it('should automatically cancel previously created and now invalid call option', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await buyer.getAddress(),
        0
      );

      await zoraV1
        .connect(buyer)
        .setApprovalForAll(erc721TransferHelper.address, true);

      await calls.connect(buyer).createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      const call = await calls.callForNFT(zoraV1.address, 0);
      expect(call.seller).to.eq(await buyer.getAddress());
    });

    it('should emit a CallCreated event ', async () => {
      const block = await ethers.provider.getBlockNumber();

      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      const events = await calls.queryFilter(
        calls.filters.CallCreated(null, null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = calls.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CallCreated');
      expect(logDescription.args.tokenId.toNumber()).to.eq(0);
      expect(logDescription.args.tokenContract).to.eq(zoraV1.address);
      expect(logDescription.args.call.seller).to.eq(
        await deployer.getAddress()
      );
    });

    it('should revert if seller is not token owner', async () => {
      await expect(
        calls.connect(otherUser).createCall(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress()
        )
      ).eventually.rejectedWith(
        'createCall must be token owner or approved operator'
      );
    });

    it('should revert if seller did not approve ERC721TransferHelper', async () => {
      await zoraV1.transferFrom(
        await deployer.getAddress(),
        await otherUser.getAddress(),
        0
      );
      await expect(
        calls.connect(otherUser).createCall(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress()
        )
      ).eventually.rejectedWith(
        'createCall must approve ZORA ERC-721 Transfer Helper from _tokenContract'
      );
    });

    it('should revert if the funds recipient is the zero address', async () => {
      await expect(
        calls.createCall(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
          ethers.constants.AddressZero,
          ethers.constants.AddressZero
        )
      ).eventually.rejectedWith('createCall must specify sellerFundsRecipient');
    });

    it('should revert if time expiration is not future block time ', async () => {
      const invalidExpirationTime = 1639905164; // Sun Dec 19 2021 04:12:44 GMT-0500 (EST)
      await expect(
        calls.createCall(
          zoraV1.address,
          0,
          ONE_HALF_ETH,
          ONE_ETH,
          invalidExpirationTime,
          ethers.constants.AddressZero,
          await sellerFundsRecipient.getAddress()
        )
      ).eventually.rejectedWith(
        'createCall _expiration must be a future block'
      );
    });
  });

  describe('#cancelCall', () => {
    beforeEach(async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );
    });

    it('should cancel a call option not yet purchased', async () => {
      await calls.cancelCall(zoraV1.address, 0);
      const call = await calls.callForNFT(zoraV1.address, 0);

      expect(call.seller).to.eq(ethers.constants.AddressZero);
    });

    it('should emit a CallCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await calls.cancelCall(zoraV1.address, 0);
      const events = await calls.queryFilter(
        calls.filters.CallCanceled(null, null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = calls.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('CallCanceled');
      expect(logDescription.args.call.seller).to.eq(
        await deployer.getAddress()
      );
    });

    it('should revert if msg.sender is not token owner or operator', async () => {
      await expect(
        calls.connect(otherUser).cancelCall(zoraV1.address, 0)
      ).eventually.rejectedWith('cancelCall must be seller or invalid call');
    });

    it('should revert if call option does not exist', async () => {
      await expect(calls.cancelCall(zoraV1.address, 1)).eventually.rejectedWith(
        'cancelCall call does not exist'
      );
    });

    it('should revert if call option has been purchased', async () => {
      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await expect(calls.cancelCall(zoraV1.address, 0)).eventually.rejectedWith(
        'cancelCall call has been purchased'
      );
    });
  });

  describe('#reclaimCall', () => {
    it('should transfer NFT back to seller', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await ethers.provider.send('evm_setNextBlockTimestamp', [
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
      ]);

      const beforeOwner = await zoraV1.ownerOf(0);
      await calls.reclaimCall(zoraV1.address, 0);
      const afterOwner = await zoraV1.ownerOf(0);

      expect(beforeOwner).to.eq(calls.address);
      expect(afterOwner).to.eq(await deployer.getAddress());

      const call = await calls.callForNFT(zoraV1.address, 0);
      expect(call.seller).to.eq(ethers.constants.AddressZero);
    });

    it('should revert if msg.sender is not seller', async () => {
      await expect(
        calls.connect(otherUser).reclaimCall(zoraV1.address, 0)
      ).eventually.rejectedWith('reclaimCall must be seller');
    });

    it('should revert if call option has not been purchased', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238406890, // Wed Dec 6th 2040
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await expect(
        calls.reclaimCall(zoraV1.address, 0)
      ).eventually.rejectedWith('reclaimCall call not purchased');
    });

    it('should revert if call option is active', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238493290, // Wed Dec 7th 2040
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );
      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await expect(
        calls.reclaimCall(zoraV1.address, 0)
      ).eventually.rejectedWith('reclaimCall call is active');
    });
  });

  describe('#buyCall', () => {
    it('should buy a call option', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2270029290,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      const beforeBuyer = await (
        await calls.callForNFT(zoraV1.address, 0)
      ).buyer;
      expect(beforeBuyer).to.eq(ethers.constants.AddressZero);

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      const afterBuyer = await (
        await calls.callForNFT(zoraV1.address, 0)
      ).buyer;
      expect(afterBuyer).to.eq(await buyer.getAddress());
    });

    it('should hold the NFT in escrow', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2270029290,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      expect(await zoraV1.ownerOf(0)).to.eq(calls.address);
    });

    it('should revert buying a call option that does not exist', async () => {
      await expect(
        calls.connect(buyer).buyCall(zoraV1.address, 0)
      ).eventually.rejectedWith('buyCall call does not exist');
    });

    it('should revert buying a call option already purchased', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2270029290,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await expect(
        calls.connect(otherUser).buyCall(zoraV1.address, 0)
      ).eventually.rejectedWith('buyCall call already purchased');
    });

    it('should revert buying an expired call option', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2270029290,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await ethers.provider.send('evm_setNextBlockTimestamp', [2270115690]);

      await expect(
        calls.connect(buyer).buyCall(zoraV1.address, 0)
      ).eventually.rejectedWith('buyCall call expired');
    });
  });

  describe('#exerciseCall', () => {
    it('should exercise a call option', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2301651690,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await calls
        .connect(buyer)
        .exerciseCall(zoraV1.address, 0, { value: ONE_ETH });

      expect(await zoraV1.ownerOf(0)).to.eq(await buyer.getAddress());
    });

    it('should revert if msg.sender is not buyer', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2301651690,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await expect(
        calls
          .connect(otherUser)
          .exerciseCall(zoraV1.address, 0, { value: ONE_ETH })
      ).eventually.rejectedWith('exerciseCall must be buyer');
    });

    it('should revert if call option expired', async () => {
      await calls.createCall(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2301651690,
        ethers.constants.AddressZero,
        await sellerFundsRecipient.getAddress()
      );

      await calls
        .connect(buyer)
        .buyCall(zoraV1.address, 0, { value: ONE_HALF_ETH });

      await ethers.provider.send('evm_setNextBlockTimestamp', [2301651690]);

      await expect(
        calls.connect(buyer).exerciseCall(zoraV1.address, 0, { value: ONE_ETH })
      ).eventually.rejectedWith('exerciseCall call expired');
    });
  });
});
