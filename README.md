### Deprecation Notice

This is a legacy NFT protocol which ZORA does not use anymore but is still alive onchain due to the nature of decentralized applications.

The media onchain is supported by multiple NFT platforms (including ZORA) for historical purposes, trading, and display but we strongly recommend using other approaches to mint and sell NFTs today (including our newer https://github.com/ourzora/zora-protocol protocol monorepo).

# V3 𓀨

This repository contains the core contracts that compose the ZORA V3 Protocol.

This protocol is a [Hyperstructure](https://www.jacob.energy/hyperstructures.html). It is unstoppable, free, expansive, permissionless, and credibly neutral.

Documentation is available at [docs.zora.co](https://docs.zora.co)

## Architecture

```
          ,-.                  ,-.
          `-'                  `-'
          /|\                  /|\
           |                    |              ,----------------.          ,-----------------.          ,-----------------------.
          / \                  / \             |ZoraMarketModule|          |ZoraModuleManager|          |ZoraProtocolFeeSettings|
      Participant            zoraDAO           `-------+--------'          `--------+--------'          `-----------+-----------'
           |                    |             registers market module               |                               |
           |                    |-------------------------------------------------->|                               |
           |                    |                      |                            |                               |
           |                    |                      |                            |  mints module ownership NFT   |
           |                    |                      |                            |------------------------------>|
           |                    |                      |                            |                               |
           |                    |                      |   transfers module ownership NFT                           |
           |                    |<----------------------------------------------------------------------------------|
           |                    |                      |                            |                               |
           |          approves market module           |                            |                               |
           |------------------------------------------>|                            |                               |
           |                    |                      |                            |                               |
           |            uses market module             |                            |                               |
           |------------------------------------------>|                            |                               |
      Participant            zoraDAO           ,-------+--------.          ,--------+--------.          ,-----------+-----------.
          ,-.                  ,-.             |ZoraMarketModule|          |ZoraModuleManager|          |ZoraProtocolFeeSettings|
          `-'                  `-'             `----------------'          `-----------------'          `-----------------------'
          /|\                  /|\
           |                    |
          / \                  / \

```

ZORA V3 has many market modules, which are individual containers a user can opt in to. All of these modules share the same approval space, and as such can save ZORA users gas in the long term by not requiring new ERC-20 and ERC-721 approvals for every market.

When a new market is registered, a ZORA Module Fee Switch NFT, or ZORF, is minted to the DAO. This fee switch is set to 0 by default. At any time, the holder of the NFT can choose to set a fee, which provides an income stream to the holder on all future transactions in that module.

Once registered, anyone is able to use the market module by approving it via the ZoraModuleManager.

## Contributing

ZORA V3 is meant to be as extensible as possible. As such, there are a number of ways for developers to contribute. This protocol is being developed in the open, and anyone can propose a module, audit a module, or suggest new module types for the community to begin using.

As the protocol matures, so too will these contribution guidelines. If you have a suggestion on how we can collaborate better on this protocol, [please let us know](#leaving-feedback).

### Registering a New Module

New modules are added to V3 in three stages. We track which stage each module is in with PR labels:

- Draft / RFC
- Community Audit
- Ready for Deployment

Note that we also include a 4th label, "ZORA Bug Bounty" for Modules that are created by the ZORA core team and ready for a community audit.

#### Draft / RFC

In this stage, the ZORA community is able to give design feedback and start discussions about what the module aims to accomplish. A new draft module can be started by [creating a new pull request](https://github.com/ourzora/v3/compare).

#### Community Audit

The ZORA v3 system has been deprecated and is no longer eligible for a community audit. Any usage of these protocols for other systems is on a AS-IS no warranty basis and this repository is no longer being maintained.

#### Registering a Module

Since the ZORA DAO is currently controlled by a multi-sig, the ZORA Core team will deploy and register audited modules manually. If the module is marked with a "Ready for Deployment" label, it will be picked up in the next available deployment window by the ZORA core team. Once deployed, the contract address will be available in the `addresses/` directory.

### Leaving Feedback

If you have suggestions or comments on how we can better collaborate on this codebase and/or the protocol as a whole, please [create an issue](https://github.com/ourzora/v3/issues/new) outlining your ideas and suggestions. We can then use the issue tracker as an open discussion forum.

## Local Development

1. Install [Foundry](https://github.com/gakonst/foundry#installation)
2. Install dependencies with `yarn` & `forge update`
3. Compile the contracts with `yarn build`
4. Run tests with `yarn test`
