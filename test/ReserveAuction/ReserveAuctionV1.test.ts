import chai, { expect } from 'chai';
import asPromised from 'chai-as-promised';
import { ethers } from 'hardhat';
import { ReserveAuctionProxy, ReserveAuctionV1 } from '../../typechain';
import {
  connectAs,
  deployReserveAuctionProxy,
  deployReserveAuctionV1,
  deployTestModule,
  deployTestModuleProxy,
  deployZoraProtocol,
  registerVersion,
} from '../utils';
import { Signer } from 'ethers';
import { Media } from '@zoralabs/core/dist/typechain';

chai.use(asPromised);

describe('ReserveAuctionV1', () => {
  let proxy: ReserveAuctionProxy;
  let reserveAuction: ReserveAuctionV1;
  let zoraV1: Media;
  let deployer: Signer;
  let otherUser: Signer;

  beforeEach(async () => {
    proxy = await deployReserveAuctionProxy();
    const module = await deployReserveAuctionV1(proxy.address);
    const zoraProtocol = await deployZoraProtocol();
    zoraV1 = zoraProtocol.media;
    const initCallData = module.interface.encodeFunctionData('initialize', [
      zoraV1.address,
    ]);
    await registerVersion(proxy, module.address, initCallData);
    reserveAuction = await connectAs<ReserveAuctionV1>(
      proxy,
      'ReserveAuctionV1'
    );
    const signers = await ethers.getSigners();
    deployer = signers[0];
    otherUser = signers[1];
  });
});
