# Chainlink Hackathon - Fall 2021

# OrcBet - A Decentralized Betting Pool Platform Based on Chainlink Technologies

For this hackathon, we develop an EVM-based decentralized betting pool platform using Chainlink technologies, called OrcBet (inspired by the words "oracle" and "bet").

## Betting Pool

Each betting pool is based on a prediction of a value (e.g. price of ETH/USD) made available by a particular Chainlink data feed. Anybody can create a betting pool, and anybody can make a bet about whether the value will be above or below some reference value after a given time.

To create a pool, these parameters are needed:

- the address of the Chainlink data feed that supplies the value
- the reference value (threshold)
- the timestamp when the actual value is evaluated against the reference value
- the address of the ERC20 token for the bet

As implemented, the pool supports any ERC20 token for the bet. But the pool manager (discussed next) currently restricts bet to be made in LINK token only. Each pool needs the pool manager for the management of the pool, including the management of fee and minimum bet amount.

## Pool Manager

The pool manager manages created pools and utilizes the Chainlink keeper to evaluate which pools are ready to close. To do this, the pool manager implements the KeeperCompatibleInterface. The deployer of the pool manager needs to make sure the pool manager is register with the keeper registry and sufficiently funded with LINK tokens. To help with security, the pool manager also manages the supported feed and tokens available for betting.

## Development

Solidity is used to implement the smart contracts. brownie is used as a development and testing framework, using the brownie starter kit provided by Chainlink as a starting point.

## Deployment

OrcBet is not yet deployed to any chain, but it can in principle be deployed to any EVM-compatible chains in which the Chainlink data feed and keeper are available. At the moment, the chains satisfying this condition are Ethereum mainnet and Polygon. No front-end is available at the moment.
