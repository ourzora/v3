Feature: Variable Supply Auctions

    ## User Story

    As a Creator,
    I want to run a Variable Supply Auction,
    so that I can conduct price discovery and right-size the market when selling my work

    Auction phases:
    - Created                   = when auction start time is in the future
    - Bid Phase                 = when bidders can place sealed bids
    - Reveal Phase              = when bidders must reveal their true bid amounts
    - Settle Phase              = when seller must choose a price point at which to settle the auction
    - Cleanup Phase             = when bidders can claim available refunds
    - Completed / Cancelled     = when an auction has been settled and all available refunds claimed / when an auction has been cancelled

    ## Job-to-be-done
    ## (how does the user story fit into the seller's broader workflow)

    Who's it for: Creator

    What's it for: To discover optimal price point and edition size when selling a digital product

    Job Map:
    1. (Define) Create digital product
    2. (Prepare) Decide on drop parameters:
    -- a. Content: _HMW help seller preview their content to potential bidders?_
    -- b. Metadata: name, symbol, initial owner, royalty bips, funds recipient, metadata renderer, and sales config
    3. (Prepare) Decide on auction parameters:
    -- a. Money: minimum viable revenue and seller funds recipient
    -- b. Time: start time, bid phase duration, reveal phase duration, settle phase duration
    4. (Confirm) Confirm drop and auction parameters look good
    5. (Execute) Create Variable Supply Auction
    6. (Monitor) Review possible settle outcomes based on revealed bids
    7. (Modify) Settle auction at a given price point, revenue, and edition size
    8. (Conclude) Share results of auction with fanbase

    ## Module Invariants

    Invariant 1: contract balance == Σ all auction totalBalances
    Invariant 2: auction settledRevenue == auction settledPricePoint * auction settledEditionSize
    Invariant 3: auction totalBalance == Σ all bidder balances, while now <= auction endOfRevealPhase

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

# TODO add Cucumber scenarios for bidder functionality
# TODO handle additional bid space bounding, beyond minimum viable revenue
## Seller sets maximum edition size commitment
## Bidder sets maximum edition size interest
# TODO address failure to reveal sad paths
# TODO address failure to settle sad paths
# TODO consider Cleanup function to delete auction, once all refunds have been claimed
# TODO run workshop for generating more VSA invariants
