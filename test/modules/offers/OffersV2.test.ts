import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import {
  Erc20TransferHelper,
  Erc1155TransferHelper,
  ListingsV2,
  TestErc1155,
  Weth,
  OffersV2,
} from '../../../typechain';
import {
  deployERC20TransferHelper,
  deployERC1155TransferHelper,
  deployOffersV2,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  mintERC1155Token,
  ONE_ETH,
  proposeModule,
  registerModule,
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  toRoundedNumber,
  TWO_ETH,
  deployTestERC1155,
  approveERC1155Transfer,
  ONE_HALF_ETH,
} from '../../utils';

chai.use(asPromised);

describe('OffersV2', () => {
  let offersV2: OffersV2;
  let testERC1155: TestErc1155;
  // let testEIP2981ERC1155: TestEip2981Erc1155;
  let weth: Weth;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc1155TransferHelper: Erc1155TransferHelper;

  beforeEach(async () => {
    const signers = await ethers.getSigners();

    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[2];

    testERC1155 = await deployTestERC1155();
    // testEIP2981ERC1155 = await deployTestEIP2981ERC1155();
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
    erc1155TransferHelper = await deployERC1155TransferHelper(
      approvalManager.address
    );

    offersV2 = await deployOffersV2(
      erc20TransferHelper.address,
      erc1155TransferHelper.address,
      weth.address
    );

    await proposeModule(proposalManager, offersV2.address);
    await registerModule(proposalManager, offersV2.address);

    await approvalManager.setApprovalForModule(offersV2.address, true);
    await approvalManager
      .connect(buyer)
      .setApprovalForModule(offersV2.address, true);

    await mintERC1155Token(
      testERC1155,
      await deployer.getAddress(),
      ethers.utils.parseUnits('50')
    );

    await approveERC1155Transfer(
      // @ts-ignore
      testERC1155,
      erc1155TransferHelper.address
    );
  });

  describe('#createOffer', () => {
    it('should create an offer for a token', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      const offer = await offersV2.offers(1);

      expect(offer.buyer).to.eq(await buyer.getAddress());
      expect(offer.tokenContract).to.eq(testERC1155.address);
      expect(offer.tokenID.toNumber()).to.eq(0);
      expect(offer.tokenAmount.toString()).to.eq(
        ethers.utils.parseUnits('25').toString()
      );
      expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
      expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
      expect(offer.status).to.eq(0);

      expect(
        (await offersV2.userToOffers(await buyer.getAddress(), 0)).toNumber()
      ).to.eq(1);

      expect(
        await offersV2.userHasActiveOffer(
          await buyer.getAddress(),
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25')
        )
      ).to.eq(true);

      expect(
        (
          await offersV2.tokenToOffers(
            testERC1155.address,
            0,
            ethers.utils.parseUnits('25'),
            0
          )
        ).toNumber()
      ).to.eq(1);
    });

    it('should revert creating a second active offer for a token', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offersV2
          .connect(buyer)
          .createOffer(
            testERC1155.address,
            0,
            ethers.utils.parseUnits('25'),
            ONE_ETH,
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`createOffer must update or cancel existing offer`
      );
    });

    it('should revert creating an offer without attaching associated funds', async () => {
      await expect(
        offersV2
          .connect(buyer)
          .createOffer(
            testERC1155.address,
            0,
            ethers.utils.parseUnits('25'),
            ONE_ETH,
            ethers.constants.AddressZero
          )
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should emit an OfferCreated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      const events = await offersV2.queryFilter(
        offersV2.filters.OfferCreated(null, null),
        block
      );

      expect(events.length).to.eq(1);
      const logDescription = offersV2.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('OfferCreated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.buyer).to.eq(await buyer.getAddress());
    });
  });

  describe('#updatePrice', () => {
    it('should increase an offer price', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.connect(buyer).updatePrice(1, TWO_ETH, { value: ONE_ETH });
      expect((await (await offersV2.offers(1)).offerPrice).toString()).to.eq(
        TWO_ETH.toString()
      );
    });

    it('should decrease an offer price', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.connect(buyer).updatePrice(1, ONE_HALF_ETH);
      expect((await (await offersV2.offers(1)).offerPrice).toString()).to.eq(
        ONE_HALF_ETH.toString()
      );
    });

    it('should revert user increasing an offer they did not create', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offersV2.connect(otherUser).updatePrice(1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(
        revert`updatePrice must be buyer from original offer`
      );
    });

    it('should revert user decreasing an offer they did not create', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offersV2.connect(otherUser).updatePrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(
        revert`updatePrice must be buyer from original offer`
      );
    });

    it('should revert increasing an offer without attaching funds', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offersV2.connect(buyer).updatePrice(1, TWO_ETH)
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });

    it('should revert updating an inactive offer', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.acceptOffer(1);
      await expect(
        offersV2.connect(buyer).updatePrice(1, ONE_HALF_ETH)
      ).eventually.rejectedWith(revert`updatePrice must be active offer`);
    });

    it('should emit an OfferUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.connect(buyer).updatePrice(1, TWO_ETH, { value: ONE_ETH });

      const events = await offersV2.queryFilter(
        offersV2.filters.OfferUpdated(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offersV2.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('OfferUpdated');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.offerPrice.toString()).to.eq(
        TWO_ETH.toString()
      );
    });
  });

  describe('#cancelOffer', () => {
    it('should cancel an active offer', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.connect(buyer).cancelOffer(1);
      expect(await (await offersV2.offers(1)).status).to.eq(1);
    });

    it('should revert canceling an inactive offer', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.acceptOffer(1);
      await expect(
        offersV2.connect(buyer).cancelOffer(1)
      ).eventually.rejectedWith(revert`cancelOffer must be active offer`);
    });

    it('should revert canceling an offer not originally made', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await expect(
        offersV2.connect(otherUser).cancelOffer(1)
      ).eventually.rejectedWith(
        revert`cancelOffer must be buyer from original offer`
      );
    });

    it('should create new offer on same token(s) after canceling', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );

      await offersV2.connect(buyer).cancelOffer(1);
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          TENTH_ETH,
          ethers.constants.AddressZero,
          {
            value: TENTH_ETH,
          }
        );
      expect((await (await offersV2.offers(2)).offerPrice).toString()).to.eq(
        TENTH_ETH.toString()
      );
    });

    it('should emit an OfferCanceled event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.connect(buyer).cancelOffer(1);
      const events = await offersV2.queryFilter(
        offersV2.filters.OfferCanceled(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offersV2.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('OfferCanceled');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(1);
    });
  });

  describe('#acceptOffer', () => {
    it('should accept an offer', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.acceptOffer(1);

      expect(
        (await testERC1155.balanceOf(await buyer.getAddress(), 0)).toString()
      ).to.eq(ethers.utils.parseUnits('25').toString());
    });

    it('should revert accepting an inactive offer', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.acceptOffer(1);
      await expect(offersV2.acceptOffer(1)).eventually.rejectedWith(
        revert`acceptOffer must be active offer`
      );
    });

    it('should revert accepting an offer from non-token holder', async () => {
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await expect(
        offersV2.connect(otherUser).acceptOffer(1)
      ).eventually.rejectedWith(
        revert`acceptOffer must own token(s) associated with offer`
      );
    });

    it('should emit an OfferAccepted event', async () => {
      const block = await ethers.provider.getBlockNumber();
      await offersV2
        .connect(buyer)
        .createOffer(
          testERC1155.address,
          0,
          ethers.utils.parseUnits('25'),
          ONE_ETH,
          ethers.constants.AddressZero,
          {
            value: ONE_ETH,
          }
        );
      await offersV2.acceptOffer(1);
      const events = await offersV2.queryFilter(
        offersV2.filters.OfferAccepted(null, null),
        block
      );
      expect(events.length).to.eq(1);
      const logDescription = offersV2.interface.parseLog(events[0]);
      expect(logDescription.name).to.eq('OfferAccepted');
      expect(logDescription.args.id.toNumber()).to.eq(1);
      expect(logDescription.args.offer.status).to.eq(2);
    });
  });
});
