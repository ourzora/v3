Feature: Variable Supply Auctions

    As a creator
    I want to run a Variable Supply Auction
    so that I can conduct price discovery and right-size the market when selling my work

    Auction phases:
    - Created
    - Bid Phase
    - Reveal Phase
    - Sizing Phase
    - Completed / Cancelled

    Background: VSA creation and bidding
        Given Seller creates a Variable Supply Auction
        And Seller and all Bidder account balances are 10 ETH
        And The following sealed bids are placed
            | account  | bid amount | sent value |
            | Bidder1  | 0.01 ETH   | 0.01 ETH   |
            | Bidder2  | 0.01 ETH   | 0.09 ETH   |
            | Bidder3  | 0.01 ETH   | 0.08 ETH   |
            | Bidder4  | 0.01 ETH   | 0.07 ETH   |
            | Bidder5  | 0.01 ETH   | 0.06 ETH   |
            | Bidder6  | 0.01 ETH   | 0.05 ETH   |
            | Bidder7  | 0.01 ETH   | 0.04 ETH   |
            | Bidder8  | 0.01 ETH   | 0.03 ETH   |
            | Bidder9  | 0.01 ETH   | 0.02 ETH   |
            | Bidder10 | 0.01 ETH   | 1.00 ETH   |
            | Bidder11 | 0.06 ETH   | 0.06 ETH   |
            | Bidder12 | 0.06 ETH   | 0.12 ETH   |
            | Bidder13 | 0.11 ETH   | 0.12 ETH   |

    Scenario: Bidders reveal bids
        When All bids are revealed
        Then The account balances should be
            | account  | balance  |
            | Seller   | 10 ETH   |
            | Bidder1  | 9.99 ETH |
            | Bidder2  | 9.99 ETH |
            | Bidder3  | 9.99 ETH |
            | Bidder4  | 9.99 ETH |
            | Bidder5  | 9.99 ETH |
            | Bidder6  | 9.99 ETH |
            | Bidder7  | 9.99 ETH |
            | Bidder8  | 9.99 ETH |
            | Bidder9  | 9.99 ETH |
            | Bidder10 | 9.94 ETH |
            | Bidder12 | 9.94 ETH |
            | Bidder13 | 9.89 ETH |

    Scenario: Seller settles VSA at 0.01 ETH
        When All bids are revealed
        And Seller settles auction at 0.01 ETH
        Then The NFT contract should be an edition of 13
        And The account balances should be
            | account  | balance   |
            | Seller   | 10.13 ETH |
            | Bidder1  | 9.99 ETH  |
            | Bidder2  | 9.99 ETH  |
            | Bidder3  | 9.99 ETH  |
            | Bidder4  | 9.99 ETH  |
            | Bidder5  | 9.99 ETH  |
            | Bidder6  | 9.99 ETH  |
            | Bidder7  | 9.99 ETH  |
            | Bidder8  | 9.99 ETH  |
            | Bidder9  | 9.99 ETH  |
            | Bidder10 | 9.99 ETH  |
            | Bidder11 | 9.99 ETH  |
            | Bidder12 | 9.99 ETH  |
            | Bidder13 | 9.99 ETH  |
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

    Scenario: Seller settles VSA at 0.06 ETH
        When All bids are revealed
        And Seller settles auction at 0.06 ETH
        Then The NFT contract should be an edition of 3
        And The account balances should be
            | account  | balance   |
            | Seller   | 10.18 ETH |
            | Bidder1  | 10 ETH    |
            | Bidder2  | 10 ETH    |
            | Bidder3  | 10 ETH    |
            | Bidder4  | 10 ETH    |
            | Bidder5  | 10 ETH    |
            | Bidder6  | 10 ETH    |
            | Bidder7  | 10 ETH    |
            | Bidder8  | 10 ETH    |
            | Bidder9  | 10 ETH    |
            | Bidder10 | 10 ETH    |
            | Bidder11 | 9.94 ETH  |
            | Bidder12 | 9.94 ETH  |
            | Bidder13 | 9.94 ETH  |
        And The following accounts should own an NFT
            | Bidder11 |
            | Bidder12 |
            | Bidder13 |

    Scenario: Seller settles VSA at 0.11 ETH
        When All bids are revealed
        And Seller settles auction at 0.11 ETH
        Then The NFT contract should be a 1 of 1
        And The account balances should be
            | account  | balance   |
            | Seller   | 10.11 ETH |
            | Bidder1  | 10 ETH    |
            | Bidder2  | 10 ETH    |
            | Bidder3  | 10 ETH    |
            | Bidder4  | 10 ETH    |
            | Bidder5  | 10 ETH    |
            | Bidder6  | 10 ETH    |
            | Bidder7  | 10 ETH    |
            | Bidder8  | 10 ETH    |
            | Bidder9  | 10 ETH    |
            | Bidder10 | 10 ETH    |
            | Bidder11 | 10 ETH    |
            | Bidder12 | 10 ETH    |
            | Bidder13 | 9.89 ETH  |
        And The following accounts should own an NFT
            | Bidder13 |

# TODO handle bid space bounding
## Seller sets maximum edition size commitment
## Bidder sets maximum edition size interest
## Seller sets minimum viable revenue
# TODO address cancel auction sad path
# TODO address failure-to-reveal sad paths
