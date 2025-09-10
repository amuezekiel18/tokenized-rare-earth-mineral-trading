# Tokenized Rare Earth Mineral Trading

A blockchain-based marketplace for tokenized trading of rare earth minerals using Clarity smart contracts on the Stacks blockchain.

## Overview

This project establishes a secure and transparent platform to tokenize mineral assets and enable peer-to-peer trading with on-chain settlement. It features two core contracts:

- Mineral Token: A fungible token representing ownership shares of a mineral asset batch.
- Supply Tracker: A logistics-focused contract tracking provenance, custody, and inventory movements.

## Key Features

- Asset tokenization with minting and burning controls
- KYC/whitelist gating for compliant trading
- Trade order placement and settlement
- Escrow-based transfers with dispute resolution
- Supply chain events and custody logs

## Getting Started

### Prerequisites
- Clarinet
- Node.js 16+
- Git

### Install
```bash
git clone https://github.com/amuezekiel18/tokenized-rare-earth-mineral-trading.git
cd tokenized-rare-earth-mineral-trading
npm install
```

### Develop
```bash
clarinet check
clarinet test
```

## Contracts

- mineral-token.clar — Fungible token with compliance controls
- supply-tracker.clar — Inventory and shipment tracking

## Security
- Strict input validation
- Role-based access controls
- On-chain event logs for auditability

## Roadmap
- Oracle integration for price feeds
- Batch certification registry
- Multi-asset trading pairs

