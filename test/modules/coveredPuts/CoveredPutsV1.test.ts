import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';
import {
  ERC20TransferHelper,
  ERC721TransferHelper,
  CoveredPutsV1,
  WETH,
  RoyaltyEngineV1,
} from '../../../typechain';
import {
  approveNFTTransfer,
  deployERC20TransferHelper,
  deployERC721TransferHelper,
  deployCoveredPutsV1,
  deployRoyaltyEngine,
  deployWETH,
  deployZoraModuleManager,
  deployProtocolFeeSettings,
  mintZoraNFT,
  ONE_HALF_ETH,
  ONE_ETH,
  registerModule,
  deployZoraProtocol,
} from '../../utils';
chai.use(asPromised);

describe('CoveredPutsV1', () => {
  let puts: CoveredPutsV1;
  let zoraV1: Media;
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

    const zoraV1Protocol = await deployZoraProtocol();
    zoraV1 = zoraV1Protocol.media;
    weth = await deployWETH();
    const feeSettings = await deployProtocolFeeSettings();
    const moduleManager = await deployZoraModuleManager(
      await deployer.getAddress(),
      feeSettings.address
    );
    await feeSettings.init(moduleManager.address, zoraV1.address);
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
    await moduleManager
      .connect(operator)
      .setApprovalForModule(puts.address, true);
    await moduleManager
      .connect(otherUser)
      .setApprovalForModule(puts.address, true);

    await mintZoraNFT(zoraV1);
    await approveNFTTransfer(zoraV1, erc721TransferHelper.address);
  });

  describe('#createPut', () => {
    it('should create a put option for an NFT', async () => {
      await puts.connect(buyer).createPut(
        zoraV1.address,
        0,
        ONE_HALF_ETH,
        ONE_ETH,
        2238366608, // Wed Dec 05 2040 19:30:08 GMT-0500 (EST)
        ethers.constants.AddressZero,
        {
          value: ONE_ETH,
        }
      );

      const put = await puts.puts(zoraV1.address, 0, 1);

      expect(put.buyer).to.eq(await buyer.getAddress());
      expect(put.seller).to.eq(ethers.constants.AddressZero);
      expect(put.currency).to.eq(ethers.constants.AddressZero);
      expect(put.premium.toString()).to.eq(ONE_HALF_ETH.toString());
      expect(put.strike.toString()).to.eq(ONE_ETH.toString());
      expect(put.expiration.toNumber()).to.eq(2238366608);
    });
  });
});
