Feature: Variable Supply Auctions

    As a creator
    I want to run a Variable Supply Auction
    so that I can conduct price discovery and right-size the market when selling my work

    Auction phases:
    - Created
    - Bid Phase
    - Reveal Phase
    - Settle Phase
    - TODO consider Cleanup phase
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

    # TODO tbd if calculate at reveal time, or save for settle time
    Scenario: Bidders reveal bids
        When All bids are revealed
        Then The revealed bids and reimbursements available should be
            | account  | bid amount | reimbursement available |
            | Bidder1  | 1 ETH      | 0 ETH                   |
            | Bidder2  | 1 ETH      | 8 ETH                   |
            | Bidder3  | 1 ETH      | 7 ETH                   |
            | Bidder4  | 1 ETH      | 6 ETH                   |
            | Bidder5  | 1 ETH      | 5 ETH                   |
            | Bidder6  | 1 ETH      | 4 ETH                   |
            | Bidder7  | 1 ETH      | 3 ETH                   |
            | Bidder8  | 1 ETH      | 2 ETH                   |
            | Bidder9  | 1 ETH      | 1 ETH                   |
            | Bidder10 | 1 ETH      | 9 ETH                   |
            | Bidder11 | 6 ETH      | 0 ETH                   |
            | Bidder12 | 6 ETH      | 3 ETH                   |
            | Bidder13 | 11 ETH     | 1 ETH                   |

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

# TODO handle bid space bounding
## Seller sets maximum edition size commitment
## Bidder sets maximum edition size interest
## Seller sets minimum viable revenue
# TODO address cancel auction sad path
# TODO address failure to reveal sad paths
# TODO address failure to settle sad paths
