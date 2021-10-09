import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { Signer } from 'ethers';
import {
  Erc20TransferHelper,
  Erc1155TransferHelper,
  OffersV2,
  TestErc1155,
  Weth,
} from '../../../typechain';
import {
  approveERC1155Transfer,
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
  ONE_HALF_ETH,
  TWO_ETH,
  TEN_ETH,
  toRoundedNumber,
  deployTestERC1155,
} from '../../utils';

chai.use(asPromised);

describe('OffersV2 integration', () => {
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
  });

  describe('Vanilla ERC1155', () => {
    beforeEach(async () => {
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

    describe('ETH offer', () => {
      async function run() {
        await offersV2
          .connect(buyer)
          .createOffer(
            testERC1155.address,
            0,
            ethers.utils.parseUnits('25'),
            ONE_ETH,
            ethers.constants.AddressZero,
            { value: ONE_ETH }
          );
      }
      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const afterBalance = await buyer.getBalance();

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });
      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offersV2
          .connect(buyer)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });
      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();

        await offersV2.connect(buyer).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });
      it('should refund canceled offer', async () => {
        const beforeBalance = await buyer.getBalance();
        await run();
        const middleBalance = await buyer.getBalance();
        await offersV2.connect(buyer).cancelOffer(1);
        const afterBalance = await buyer.getBalance();

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });
      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await offersV2.signer.getBalance();
        await run();
        await offersV2.acceptOffer(1);
        const afterBalance = await offersV2.signer.getBalance();

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(ONE_ETH)),
          10
        );
      });
      it('should transfer tokens to buyer after accepted offer', async () => {
        await run();
        await offersV2.acceptOffer(1);

        expect(
          (await testERC1155.balanceOf(await buyer.getAddress(), 0)).toString()
        ).to.eq(ethers.utils.parseUnits('25').toString());
      });
    });

    describe('WETH offer', () => {
      beforeEach(async () => {
        await weth.connect(buyer).deposit({ value: TEN_ETH });
        await weth.connect(buyer).approve(erc20TransferHelper.address, TEN_ETH);
      });

      async function run() {
        await offersV2
          .connect(buyer)
          .createOffer(
            testERC1155.address,
            0,
            ethers.utils.parseUnits('25'),
            ONE_ETH,
            weth.address,
            { value: ONE_ETH }
          );
      }

      it('should withdraw offer from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(
          toRoundedNumber(beforeBalance.sub(afterBalance))
        ).to.be.approximately(toRoundedNumber(ONE_ETH), 5);
      });

      it('should withdraw offer increase from buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        await offersV2
          .connect(buyer)
          .updatePrice(1, TWO_ETH, { value: ONE_ETH });

        const afterBalance = await weth.balanceOf(await buyer.getAddress());
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(TWO_ETH)),
          10
        );
      });

      it('should refund offer decrease to buyer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();

        await offersV2.connect(buyer).updatePrice(1, ONE_HALF_ETH);

        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_HALF_ETH)),
          10
        );
      });

      it('should refund canceled offer', async () => {
        const beforeBalance = await weth.balanceOf(await buyer.getAddress());
        await run();
        const middleBalance = await weth.balanceOf(await buyer.getAddress());
        await offersV2.connect(buyer).cancelOffer(1);
        const afterBalance = await weth.balanceOf(await buyer.getAddress());

        expect(toRoundedNumber(middleBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.sub(ONE_ETH)),
          10
        );
        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(middleBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer funds from accepted offer to seller', async () => {
        const beforeBalance = await weth.balanceOf(
          await offersV2.signer.getAddress()
        );
        await run();
        await offersV2.acceptOffer(1);
        const afterBalance = await weth.balanceOf(
          await offersV2.signer.getAddress()
        );

        expect(toRoundedNumber(afterBalance)).to.be.approximately(
          toRoundedNumber(beforeBalance.add(ONE_ETH)),
          10
        );
      });

      it('should transfer tokens to buyer after accepted offer', async () => {
        await run();
        await offersV2.acceptOffer(1);

        expect(
          (await testERC1155.balanceOf(await buyer.getAddress(), 0)).toString()
        ).to.eq(ethers.utils.parseUnits('25').toString());
      });
    });
  });

  // describe('EIP2981 ERC1155', () => {
  //   beforeEach(async () => {});
  //   describe('ETH offer', () => {
  //     async function run() {}
  //     it('should withdraw offer from buyer', async () => {});
  //     it('should withdraw offer increase from buyer', async () => {});
  //     it('should refund offer decrease to buyer', async () => {});
  //     it('should refund canceled offer', async () => {});
  //     it('should transfer funds from accepted offer to seller', async () => {});
  //     it('should transfer tokens to buyer after accepted offer', async () => {});
  //   });
  //   describe('WETH offer', () => {
  //     beforeEach(async () => {});
  //     async function run() {}
  //     it('should withdraw offer from buyer', async () => {});
  //     it('should withdraw offer increase from buyer', async () => {});
  //     it('should refund offer decrease to buyer', async () => {});
  //     it('should refund canceled offer', async () => {});
  //     it('should transfer funds from accepted offer to seller', async () => {});
  //     it('should transfer tokens to buyer after accepted offer', async () => {});
  //   });
  // });
});
