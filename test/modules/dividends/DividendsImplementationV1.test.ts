import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  DividendsDeployerV1,
  TestErc721,
  DividendsImplementationV1,
  DividendsImplementationV1Factory,
} from '../../../typechain';
import { deployTestERC271, ONE_ETH, revert } from '../../utils';
import { Signer } from 'ethers';

chai.use(asPromised);

describe('DividendsImplementationV1', () => {
  let dividendsDeployer: DividendsDeployerV1;
  let testERC721: TestErc721;
  let deployer: Signer;
  let instance: DividendsImplementationV1;

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
    const tx = await dividendsDeployer.deployDividendsContract(
      testERC721.address
    );
    const receipt = await tx.wait();
    const event = receipt.events.find(
      (x) => x.event === 'DividendsContractDeployed'
    );
    instance = DividendsImplementationV1Factory.connect(
      event.args.instance,
      deployer
    );
  });

  describe('#receive', () => {
    it('should increase the totalIncome value', async () => {
      expect((await instance.totalIncome()).toString()).to.eq('0');
      await deployer.sendTransaction({ to: instance.address, value: ONE_ETH });

      expect((await instance.totalIncome()).toString()).to.eq(
        ONE_ETH.toString()
      );
    });

    it('should emit a FundsReceived event', async () => {
      await deployer.sendTransaction({
        to: instance.address,
        value: ONE_ETH,
      });
      const events = await instance.queryFilter(
        instance.filters.FundsReceived(null)
      );
      expect(events.length).to.eq(1);

      expect(events[0].args.amount.toString()).to.eq(ONE_ETH.toString());
    });
  });

  describe('#claimableDividendsForToken', async () => {});
});
