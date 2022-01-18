import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredPutsV1,
  TestERC721,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  mintERC721Token,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployTestERC721,
  deployCoveredPutsV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleManager,
  deployProtocolFeeSettings,
  THOUSANDTH_ETH,
  ONE_HALF_ETH,
  ONE_ETH,
  registerModule,
  toRoundedNumber,
} from '../../utils';
import { MockContract } from 'ethereum-waffle';
chai.use(asPromised);
describe('CoveredCallsV1 integration', () => {
  let puts: CoveredPutsV1;
  let testERC721: TestERC721;
  let weth: WETH;
  let deployer: Signer;
  let buyer: Signer;
  let otherUser: Signer;
  let operator: Signer;
  let erc20TransferHelper: ERC20TransferHelper;
  let erc721TransferHelper: ERC721TransferHelper;
  let royaltyEngine: RoyaltyEngineV1;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    deployer = signers[0];
    buyer = signers[1];
    otherUser = signers[3];
    operator = signers[4];

    testERC721 = await deployTestERC721();
    weth = await deployWETH();
    const feeSettings = await deployProtocolFeeSettings();
    const moduleManager = await deployZoraModuleManager(
      await deployer.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(moduleManager.address, testERC721.address);
    erc20TransferHelper = await deployERC20TransferHelper(
      moduleManager.address
    );
    erc721TransferHelper = await deployERC721TransferHelper(
      moduleManager.address
    );
    royaltyEngine = await deployRoyaltyEngine();
    puts = await deployCoveredPutsV1(
      erc20TransferHelper.address,
      erc721TransferHelper.address,
      royaltyEngine.address,
      feeSettings.address,
      weth.address
    );

    await registerModule(moduleManager, puts.address);

    await moduleManager.setApprovalForModule(puts.address, true);
    await moduleManager.connect(buyer).setApprovalForModule(puts.address, true);
  });

  describe('ZORA V1 NFT', () => {
    beforeEach(async () => {
      await (royaltyEngine as unknown as MockContract).mock.getRoyalty.returns(
        [await deployer.getAddress()],
        [THOUSANDTH_ETH.mul(150)]
      );
      await mintERC721Token(testERC721, await deployer.getAddress());
      await approveNFTTransfer(
        // @ts-ignore
        testERC721,
        erc721TransferHelper.address
      );
    });

    describe('ETH', () => {
      describe('put option purchased', () => {
        async function run() {
          await puts.connect(buyer).createPut(
            testERC721.address,
            0,
            ONE_HALF_ETH,
            ONE_ETH,
            2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
            ethers.constants.AddressZero,
            {
              value: ONE_ETH,
            }
          );

          await puts.buyPut(testERC721.address, 0, 1, { value: ONE_HALF_ETH });
        }

        it('should withdraw premium from seller', async () => {
          const beforeBalance = await deployer.getBalance();
          await run();
          const afterBalance = await deployer.getBalance();

          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });

        it('should transfer premium amount to buyer', async () => {
          const beforeBalance = await buyer.getBalance();
          await run();
          const afterBalance = await buyer.getBalance();

          // beforeBalance - 1 ETH strike escrow + 0.5 ETH premium = -0.5 ETH
          expect(
            toRoundedNumber(beforeBalance.sub(afterBalance))
          ).to.be.approximately(toRoundedNumber(ONE_HALF_ETH), 5);
        });
      });
    });
  });
});
