# Chainlink Hackathon - Fall 2021

# OrcBet - A Decentralized Betting Pool Platform Based on Chainlink Technologies

For this hackathon, we develop an EVM-based decentralized betting pool platform using Chainlink technologies, called OrcBet (inspired by the words "oracle" and "bet").

## Betting Pool

Each betting pool is based on a prediction of a value (e.g. price of ETH/USD) made available by a particular [Chainlink data feed](https://docs.chain.link/docs/using-chainlink-reference-contracts/). Anybody can create a betting pool, and anybody can make a bet about whether the value will be above or below some reference value after a given time.

To create a pool, these parameters are needed:

- the address of the Chainlink data feed that supplies the value
- the reference value (threshold)
- the timestamp when the actual value is evaluated against the reference value
- the address of the ERC20 token for the bet

Anybody can be a bettor. An address wishing to bet can allocate amount to both sides of the bet; it can also add to the bet, but once a bet is made, there is no way to withdraw the bet until the pool is closed. Because of the binary nature of the bet, the bet amount can be divided into two categories: bet amount above and bet amount below. At the close of the pool, the bet amount is distributed in the following ways:

- if the value equals to the reference value, all the bettors get back their bet amount minus fees
- if the value is above the reference value, each bettor with non-zero amount as part of bet amount above gets their bet back plus a portion of the bet amount below; the bet amount below is distributed in proportion to the bet amount above proportion
- if the value is below the reference value, see the immediately preceding description, switching "above" and "below"

Fees are collected for each bet; the fee proportion is determined by the pool manager. One purpose of the collecing the fees is to fund the Chainlink keeper.

As implemented, the pool supports any ERC20 token for the bet. But the pool manager currently restricts bet to be made in LINK token only. Each pool needs the pool manager for the management of the pool, including the management of fee and minimum bet amount.

## Pool Manager

The pool manager manages created pools and utilizes the [Chainlink keeper](https://docs.chain.link/docs/chainlink-keepers/introduction/) to evaluate which pools are ready to close. To do this, the pool manager implements the [KeeperCompatibleInterface](https://docs.chain.link/docs/chainlink-keepers/compatible-contracts/). The deployer of the pool manager needs to make sure the pool manager is register with the keeper registry and sufficiently funded with LINK tokens. To help with security, the pool manager also manages the supported feed and tokens available for betting.

## Development

Solidity is used to implement the smart contracts. [brownie](https://eth-brownie.readthedocs.io/en/stable/) is used as a development and testing framework, using the [brownie starter kit](https://github.com/smartcontractkit/chainlink-mix) provided by Chainlink as a starting point.

## Deployment

OrcBet is not yet deployed to any chain, but it can in principle be deployed to any EVM-compatible chains in which the Chainlink data feed and keeper are available. At the moment, the chains satisfying this condition are Ethereum mainnet and Polygon. No front-end is available at the moment.
