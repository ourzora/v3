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
        And Seller, Seller Funds Recipient, and all Bidder account balances are 100 ETH
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
            | Bidder14 | 2 ETH      | 2 ETH      |

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
            | Bidder14 | 2 ETH      |

    Scenario: Seller settles VSA at 1 ETH
        When All bids are revealed
        And Seller settles auction at 1 ETH
        Then The NFT contract should be an edition of 14
        And The Seller Funds Recipient account balance should be 114 ETH
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
            | Bidder14 |
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
            | Bidder14 | 1 ETH            |

    Scenario: Seller settles VSA at 6 ETH
        When All bids are revealed
        And Seller settles auction at 6 ETH
        Then The NFT contract should be an edition of 3
        And The Seller Funds Recipient account balance should be 118 ETH
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
            | Bidder14 | 2 ETH            |

    Scenario: Seller settles VSA at 11 ETH
        When All bids are revealed
        And Seller settles auction at 11 ETH
        Then The NFT contract should be a 1 of 1
        And The Seller Funds Recipient account balance should be 111 ETH
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
            | Bidder14 | 2 ETH            |

    Scenario: Seller cannot settle VSA at 2 ETH
        When All bids are revealed
        And Seller settles auction at 2 ETH
        Then The Seller should receive a Does Not Meet Minimum Revenue error

# TODO handle additional bid space bounding, beyond minimum viable revenue
## Seller sets maximum edition size commitment
## Bidder sets maximum edition size interest
# TODO address failure to reveal sad paths
# TODO address failure to settle sad paths
# TODO consider Cleanup function to delete auction, once all refunds have been claimed
# TODO add Cucumber scenarios for bidder functionality
