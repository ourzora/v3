Feature: Variable Supply Auctions

    As a creator
    I want to run a Variable Supply Auction
    so that I can conduct price discovery and right-size the market when selling my work

    Auction phases:
    - Created
    - Bid Phase
    - Reveal Phase
    - Settle Phase
    - Completed / Cancelled

    Background: VSA creation and bidding
        Given Seller creates a Variable Supply Auction
        And Seller and all Bidder account balances are 100 ETH
        And The following sealed bids are placed
            | account  | bid amount | sent value |
            | Bidder1  | 1 ETH      | 1 ETH      |
            | Bidder2  | 1 ETH      | 9 ETH      |
            | Bidder3  | 1 ETH      | 8 ETH      |
            | Bidder4  | 1 ETH      | 7 ETH      |
            | Bidder5  | 1 ETH      | 6 ETH      |
            | Bidder6  | 1 ETH      | 5 ETH      |
            | Bidder7  | 1 ETH      | 4 ETH      |
            | Bidder8  | 1 ETH      | 3 ETH      |
            | Bidder9  | 1 ETH      | 2 ETH      |
            | Bidder10 | 1 ETH      | 10 ETH     |
            | Bidder11 | 6 ETH      | 6 ETH      |
            | Bidder12 | 6 ETH      | 9 ETH      |
            | Bidder13 | 11 ETH     | 12 ETH     |

    Scenario: Bidders reveal bids
        When All bids are revealed
        Then The revealed bids should be
            | account  | bid amount |
            | Bidder1  | 1 ETH      |
            | Bidder2  | 1 ETH      |
            | Bidder3  | 1 ETH      |
            | Bidder4  | 1 ETH      |
            | Bidder5  | 1 ETH      |
            | Bidder6  | 1 ETH      |
            | Bidder7  | 1 ETH      |
            | Bidder8  | 1 ETH      |
            | Bidder9  | 1 ETH      |
            | Bidder10 | 1 ETH      |
            | Bidder11 | 6 ETH      |
            | Bidder12 | 6 ETH      |
            | Bidder13 | 11 ETH     |

    Scenario: Seller settles VSA at 1 ETH
        When All bids are revealed
        And Seller settles auction at 1 ETH
        Then The NFT contract should be an edition of 13
        And The account balances should be
            | account  | balance |
            | Seller   | 113 ETH |
            | Bidder1  | 99 ETH  |
            | Bidder2  | 99 ETH  |
            | Bidder3  | 99 ETH  |
            | Bidder4  | 99 ETH  |
            | Bidder5  | 99 ETH  |
            | Bidder6  | 99 ETH  |
            | Bidder7  | 99 ETH  |
            | Bidder8  | 99 ETH  |
            | Bidder9  | 99 ETH  |
            | Bidder10 | 99 ETH  |
            | Bidder11 | 99 ETH  |
            | Bidder12 | 99 ETH  |
            | Bidder13 | 99 ETH  |
        And The following accounts should own 1 NFT
            | account  |
            | Bidder1  |
            | Bidder2  |
            | Bidder3  |
            | Bidder4  |
            | Bidder5  |
            | Bidder6  |
            | Bidder7  |
            | Bidder8  |
            | Bidder9  |
            | Bidder10 |
            | Bidder11 |
            | Bidder12 |
            | Bidder13 |
        And The available refunds should be
            | account  | available refund |
            | Bidder1  | 0 ETH            |
            | Bidder2  | 8 ETH            |
            | Bidder3  | 7 ETH            |
            | Bidder4  | 6 ETH            |
            | Bidder5  | 5 ETH            |
            | Bidder6  | 4 ETH            |
            | Bidder7  | 3 ETH            |
            | Bidder8  | 2 ETH            |
            | Bidder9  | 1 ETH            |
            | Bidder10 | 9 ETH            |
            | Bidder11 | 5 ETH            |
            | Bidder12 | 8 ETH            |
            | Bidder13 | 11 ETH           |

    Scenario: Seller settles VSA at 6 ETH
        When All bids are revealed
        And Seller settles auction at 6 ETH
        Then The NFT contract should be an edition of 3
        And The account balances should be
            | account  | balance  |
            | Seller   | 118 ETH  |
            | Bidder1  | 100 ETH  |
            | Bidder2  | 100 ETH  |
            | Bidder3  | 1000 ETH |
            | Bidder4  | 100 ETH  |
            | Bidder5  | 100 ETH  |
            | Bidder6  | 100 ETH  |
            | Bidder7  | 100 ETH  |
            | Bidder8  | 100 ETH  |
            | Bidder9  | 100 ETH  |
            | Bidder10 | 100 ETH  |
            | Bidder11 | 94 ETH   |
            | Bidder12 | 94 ETH   |
            | Bidder13 | 94 ETH   |
        And The following accounts should own 1 NFT
            | Bidder11 |
            | Bidder12 |
            | Bidder13 |
        And The available refunds should be
            | account  | available refund |
            | Bidder1  | 1 ETH            |
            | Bidder2  | 9 ETH            |
            | Bidder3  | 8 ETH            |
            | Bidder4  | 7 ETH            |
            | Bidder5  | 6 ETH            |
            | Bidder6  | 5 ETH            |
            | Bidder7  | 4 ETH            |
            | Bidder8  | 3 ETH            |
            | Bidder9  | 2 ETH            |
            | Bidder10 | 10 ETH           |
            | Bidder11 | 0 ETH            |
            | Bidder12 | 3 ETH            |
            | Bidder13 | 6 ETH            |

    Scenario: Seller settles VSA at 11 ETH
        When All bids are revealed
        And Seller settles auction at 11 ETH
        Then The NFT contract should be a 1 of 1
        And The account balances should be
            | account  | balance |
            | Seller   | 111 ETH |
            | Bidder1  | 100 ETH |
            | Bidder2  | 100 ETH |
            | Bidder3  | 100 ETH |
            | Bidder4  | 100 ETH |
            | Bidder5  | 100 ETH |
            | Bidder6  | 100 ETH |
            | Bidder7  | 100 ETH |
            | Bidder8  | 100 ETH |
            | Bidder9  | 100 ETH |
            | Bidder10 | 100 ETH |
            | Bidder11 | 100 ETH |
            | Bidder12 | 100 ETH |
            | Bidder13 | 89 ETH  |
        And The following accounts should own 1 NFT
            | Bidder13 |
        And The available refunds should be
            | account  | available refund |
            | Bidder1  | 1 ETH            |
            | Bidder2  | 9 ETH            |
            | Bidder3  | 8 ETH            |
            | Bidder4  | 7 ETH            |
            | Bidder5  | 6 ETH            |
            | Bidder6  | 5 ETH            |
            | Bidder7  | 4 ETH            |
            | Bidder8  | 3 ETH            |
            | Bidder9  | 2 ETH            |
            | Bidder10 | 10 ETH           |
            | Bidder11 | 6 ETH            |
            | Bidder12 | 9 ETH            |
            | Bidder13 | 1 ETH            |

# TODO handle additional bid space bounding, beyond minimum viable revenue
## Seller sets maximum edition size commitment
## Bidder sets maximum edition size interest
# TODO address failure to reveal sad paths
# TODO address failure to settle sad paths
# TODO consider Cleanup function to delete auction, once all refunds have been claimed
# TODO add Cucumber feature for bidder functionality
