import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  Erc20TransferHelper,
  Erc721TransferHelper,
  OffersV1,
  TestErc721,
  Weth,
} from '../../../typechain';

import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployOffersV1,
  deployTestERC271,
  deployWETH,
  deployZoraModuleApprovalsManager,
  deployZoraProposalManager,
  deployZoraProtocol,
  mintZoraNFT,
  mintERC721Token,
  ONE_ETH,
  ONE_HALF_ETH,
  proposeModule,
  registerModule,
  revert,
  TENTH_ETH,
  THOUSANDTH_ETH,
  THREE_ETH,
  toRoundedNumber,
  TWO_ETH,
} from '../../utils';

chai.use(asPromised);

describe('OffersV1', () => {
  let offers: OffersV1;
  let zoraV1: Media;
  let testERC721: TestErc721;
  let weth: Weth;
  let deployer: Signer;
  let buyerA: Signer;
  let otherUser: Signer;
  let erc20TransferHelper: Erc20TransferHelper;
  let erc721TransferHelper: Erc721TransferHelper;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyerA = signers[1];
    otherUser = signers[2];

    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;

    testERC721 = await deployTestERC271();
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

    offers = await deployOffersV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      zoraV1.address,
      weth.address
    );

    await proposeModule(proposalManager, offers.address);
    await registerModule(proposalManager, offers.address);

    await approvalManager.setApprovalForModule(offers.address, true);
    await approvalManager
      .connect(buyerA)
      .setApprovalForModule(offers.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createOffer', () => {
    it('should create an offer', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });
      const offer = await offers.offers(1);

      expect(offer.buyer).to.eq(await buyerA.getAddress());
      expect(offer.tokenContract).to.eq(zoraV1.address);
      expect(offer.tokenId.toNumber()).to.eq(0);
      expect(offer.offerPrice.toString()).to.eq(ONE_ETH.toString());
      expect(offer.offerCurrency).to.eq(ethers.constants.AddressZero);
      expect(offer.status).to.eq(0);

      expect(
        (await offers.userToOffers(await buyerA.getAddress(), 0)).toNumber()
      ).to.eq(1);

      expect(
        await offers.userHasActiveOffer(
          await buyerA.getAddress(),
          zoraV1.address,
          0
        )
      ).to.eq(true);

      expect((await offers.nftToOffers(zoraV1.address, 0, 0)).toNumber()).to.eq(
        1
      );
    });

    it('should revert on attempt to create second offer while first is active', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });

      await expect(
        offers
          .connect(buyerA)
          .createOffer(
            zoraV1.address,
            0,
            TWO_ETH,
            ethers.constants.AddressZero,
            { value: TWO_ETH }
          )
      ).eventually.rejectedWith(
        revert`createOffer must update or cancel existing offer`
      );
    });

    it('should revert on attempt to create offer without attaching correct amt funds', async () => {
      await expect(
        offers
          .connect(buyerA)
          .createOffer(
            zoraV1.address,
            0,
            ONE_ETH,
            ethers.constants.AddressZero,
            {
              value: ONE_HALF_ETH,
            }
          )
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });
  });

  describe('#updateOffer', () => {
    it('should increase the offer price', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });
      await offers.connect(buyerA).updatePrice(1, TWO_ETH, { value: ONE_ETH });
      expect((await (await offers.offers(1)).offerPrice).toString()).to.eq(
        TWO_ETH.toString()
      );
    });

    it('should decrease the offer price', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });

      await offers.connect(buyerA).updatePrice(1, ONE_HALF_ETH);
      expect((await (await offers.offers(1)).offerPrice).toString()).to.eq(
        ONE_HALF_ETH.toString()
      );
    });

    it('should revert on attempt to increase offer not originally created', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });
      await expect(
        offers.connect(otherUser).updatePrice(1, TWO_ETH, { value: TWO_ETH })
      ).eventually.rejectedWith(
        revert`updatePrice must be buyer from original offer`
      );
    });

    it('should revert on attempt to increase offer without attaching funds', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });
      await expect(
        offers.connect(buyerA).updatePrice(1, TWO_ETH)
      ).eventually.rejectedWith(
        revert`_handleIncomingTransfer msg value less than expected amount`
      );
    });
  });

  describe('#cancelOffer', () => {
    it('should cancel an active offer', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });

      await offers.connect(buyerA).cancelOffer(1);

      expect(await (await offers.offers(1)).status).to.eq(1);
    });

    it('should allow user to create a new offer on the same NFT', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });

      await offers.connect(buyerA).cancelOffer(1);

      await offers
        .connect(buyerA)
        .createOffer(
          zoraV1.address,
          0,
          TENTH_ETH,
          ethers.constants.AddressZero,
          {
            value: TENTH_ETH,
          }
        );

      expect((await (await offers.offers(2)).offerPrice).toString()).to.eq(
        TENTH_ETH.toString()
      );
    });
  });

  describe('#acceptOffer', () => {
    it('should allow a token owner to accept an offer', async () => {
      await offers
        .connect(buyerA)
        .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
          value: ONE_ETH,
        });

      await offers.acceptOffer(1);

      expect(await zoraV1.ownerOf(0)).to.eq(await buyerA.getAddress());
    });
  });

  it('should revert a user from accepting an offer on behalf of a token holder', async () => {
    await offers
      .connect(buyerA)
      .createOffer(zoraV1.address, 0, ONE_ETH, ethers.constants.AddressZero, {
        value: ONE_ETH,
      });

    await expect(
      offers.connect(otherUser).acceptOffer(1)
    ).eventually.rejectedWith(
      revert`acceptOffer must own token associated with offer`
    );
  });
});
