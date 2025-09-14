# Flight-Delay-Insurance-DApp

Decentralized flight delay insurance built with Clarity (Stacks). This project demonstrates a simple, clean, and logically correct on-chain core for:

- Flight data reporting (oracle-fed via transactions)
- Premium calculation using simple risk indicators
- Instant payout processing based on reported flight status

The design intentionally avoids cross-contract calls and trait usage for clarity and to keep the system self-contained within a single project.

## Overview

This DApp allows users to purchase insurance for a given flight. If the flight is reported as delayed beyond a threshold or cancelled, the insured user can claim a payout.

- Policies are keyed by (policy-id) and reference a flight (airline, flight-number, departure-date)
- A minimal oracle-like mechanism lets designated reporters submit flight statuses on-chain
- Premiums are computed using a simple rules-based model
- Payouts are disbursed to the policy holder when a qualifying status is recorded

Note: This repository models the logic only. Any off-chain data ingestion and UI are out of scope.

## Components

- flight-data-oracle: Records flight statuses in a tamper-evident way. Reporters are whitelisted by the contract admin.
- instant-payout-processor: Handles policy lifecycle and payouts triggered by flight statuses.
- premium-calculator: Provides a deterministic premium quote using historical risk hints provided at policy creation (no external calls).

## Data Model

- Flight: { airline: (buff 8), number: uint, date-yyyymmdd: uint }
- Status: u0=unknown, u1=on-time, u2=delayed, u3=cancelled
- Policy: { holder: principal, flight: Flight, premium: uint, payout: uint, active: bool }

## User Flows

1) Quote
- A user requests a quote by providing flight basics and a risk-hint (e.g., historical delay ratio in basis points). The premium-calculator returns a premium amount.

2) Purchase
- The user purchases a policy by paying the quoted premium to the payout processor. The policy becomes active until the flight is resolved.

3) Report
- A whitelisted reporter submits a status update for the flight (on-time, delayed, cancelled) via the oracle contract.

4) Claim
- If a qualifying status is recorded (delayed or cancelled), the policy holder calls claim to receive the payout. Policies are deactivated after a claim.

## Security Considerations

- Reporters: Only admin-approved principals can report statuses.
- Immutability: Records are append-only with last-known status surfaced for convenience.
- No external calls: Premiums and payouts are deterministic and computed on-chain.
- Funds handling: In a real deployment, STX transfers should be carefully audited and guarded; here, transfers are simulated through contract balance accounting to keep focus on logic.

## Development

Prerequisites:
- Node.js LTS
- Clarinet
- Git and GitHub CLI (gh)

Commands:
- clarinet check: Validate all contracts.
- clarinet contract new <name>: Scaffold a new Clarity contract.

## Branching Strategy

- main: Initialization files and documentation only.
- development: Active contract development (Clarity files and tests).

## License

MIT