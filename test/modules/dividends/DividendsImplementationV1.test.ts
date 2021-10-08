import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import {
  DividendsDeployerV1,
  TestErc721,
  DividendsImplementationV1,
  DividendsImplementationV1Factory,
} from '../../../typechain';
import {
  deployTestERC271,
  ONE_ETH,
  revert,
  toRoundedNumber,
} from '../../utils';
import { Signer } from 'ethers';
import { parseEther } from 'ethers/lib/utils';

chai.use(asPromised);

describe('DividendsImplementationV1', () => {
  let dividendsDeployer: DividendsDeployerV1;
  let testERC721: TestErc721;
  let user: Signer;
  let instance: DividendsImplementationV1;

  beforeEach(async () => {
    user = (await ethers.getSigners())[0];
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
      user
    );
  });

  describe('#receive', () => {
    it('should increase the totalIncome value', async () => {
      expect((await instance.totalIncome()).toString()).to.eq('0');
      await user.sendTransaction({ to: instance.address, value: ONE_ETH });

      expect((await instance.totalIncome()).toString()).to.eq(
        ONE_ETH.toString()
      );
    });

    it('should emit a FundsReceived event', async () => {
      await user.sendTransaction({
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

  describe('#claimableDividendsForToken', async () => {
    beforeEach(async () => {
      await testERC721.mint(await user.getAddress(), 1);
      await testERC721.mint(await user.getAddress(), 2);
      await testERC721.mint(await user.getAddress(), 3);
      await testERC721.mint(await user.getAddress(), 4);
    });
    it('should return the claimable dividends for a token ID', async () => {
      await user.sendTransaction({ to: instance.address, value: ONE_ETH });

      expect((await instance.claimableDividendsForToken(1)).toString()).to.eq(
        parseEther('0.25').toString()
      );
    });
  });

  describe('#claimDividendsForToken', async () => {
    beforeEach(async () => {
      await testERC721.mint(await user.getAddress(), 1);
      await testERC721.mint(await user.getAddress(), 2);
      await testERC721.mint(await user.getAddress(), 3);
      await testERC721.mint(await user.getAddress(), 4);
      await user.sendTransaction({ to: instance.address, value: ONE_ETH });
    });

    it('should claim the dividends for the token', async () => {
      const beforeBalance = await user.getBalance();
      await instance.claimDividendsForToken(1);
      const afterBalance = await user.getBalance();

      expect(toRoundedNumber(afterBalance.sub(beforeBalance))).to.approximately(
        toRoundedNumber(parseEther('0.25')),
        1
      );
    });

    it('should emit a DividendsClaimed event', async () => {
      await instance.claimDividendsForToken(1);
      const events = await instance.queryFilter(
        instance.filters.DividendsClaimed(null, null, null)
      );
      expect(events.length).to.eq(1);
      expect(events[0].args.amount.toString()).to.eq(
        parseEther('0.25').toString()
      );
      expect(events[0].args.recipient).to.eq(await user.getAddress());
      expect(events[0].args.tokenID.toNumber()).to.eq(1);
    });

    it('should set the nextWithdrawalBase for the token', async () => {
      await instance.claimDividendsForToken(1);

      expect((await instance.nextWithdrawalBase(1)).toString()).to.eq(
        ONE_ETH.toString()
      );
    });
  });
});
