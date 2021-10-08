import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  DividendsDeployerV1,
  TestErc721,
  DividendsImplementationV1Factory,
} from '../../../typechain';
import { deployBadERC721, deployTestERC271, revert } from '../../utils';
import { Signer } from 'ethers';

chai.use(asPromised);

describe('DividendsDeployerV1', () => {
  let dividendsDeployer: DividendsDeployerV1;
  let testERC721: TestErc721;
  let deployer: Signer;

  beforeEach(async () => {
    deployer = (await ethers.getSigners())[0];
    testERC721 = await deployTestERC271();
    const DividendsImplementationFactory = await ethers.getContractFactory(
      'DividendsImplementationV1'
    );
    const implementation = await DividendsImplementationFactory.deploy();
    const DividendsDeployerFactory = await ethers.getContractFactory(
      'DividendsDeployerV1'
    );
    dividendsDeployer = (await DividendsDeployerFactory.deploy(
      implementation.address
    )) as DividendsDeployerV1;
  });

  describe('#deployDividendsContract', async () => {
    it('should deploy a dividends implementation clone', async () => {
      const tx = await dividendsDeployer.deployDividendsContract(
        testERC721.address
      );
      const receipt = await tx.wait();
      const event = receipt.events.find(
        (x) => x.event === 'DividendsContractDeployed'
      );
      const instance = event.args.instance;

      expect(
        await dividendsDeployer.nftContractToDividendsContract(
          testERC721.address
        )
      ).to.eq(instance);

      expect(
        await DividendsImplementationV1Factory.connect(instance, deployer).nft()
      ).to.eq(testERC721.address);
    });

    it('should revert if the NFT contract has had a dividends implementation deployed', async () => {
      await dividendsDeployer.deployDividendsContract(testERC721.address);

      await expect(
        dividendsDeployer.deployDividendsContract(testERC721.address)
      ).eventually.rejectedWith(
        revert`deployDividendsContract dividends contract already deployed for given NFT contract`
      );
    });

    it('should revert if the NFT does not implement IERC721Enumerable', async () => {
      const badNFT = await deployBadERC721();

      await expect(
        dividendsDeployer.deployDividendsContract(badNFT.address)
      ).eventually.rejectedWith(
        revert`initialize supplied NFT does not support IERC721Enumerable interface`
      );
    });
  });
});
