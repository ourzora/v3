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

## Local Development

1. Install [Foundry](https://github.com/gakonst/foundry#installation)
2. Install dependencies with `yarn`
3. Compile the contracts with `yarn build`
4. Run tests with `yarn test`
