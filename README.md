# SentinelVault: AI-Enhanced Multisig Smart Contract

## Table of Contents
* [Introduction]
* [Core Concepts]
* [Security Architecture]
* [Dynamic Risk Scoring]
* [Technical Specifications]
* [Contract State & Constants]
* [API Reference: Private Functions]
* [API Reference: Read-Only Functions]
* [API Reference: Public Administrative Functions]
* [API Reference: Transaction Lifecycle]
* [Error Code Reference]
* [Development and Deployment]
* [Contribution Guidelines]
* [Security Audits]
* [License]

---

## Introduction

I am pleased to present **SentinelVault**, a next-generation multisignature wallet implementation for the Stacks blockchain. This contract transcends traditional M-of-N multisig logic by integrating an **AI-driven security layer**. Unlike static wallets where the threshold of required signatures is fixed, SentinelVault adjusts its security requirements in real-time based on the perceived risk of a transaction, as determined by a specialized AI Oracle.

This implementation is designed for institutional-grade asset management, DAOs requiring granular security, and individuals who want an automated "sanity check" on their high-value transfers.

## Core Concepts

### The AI-Driven Paradigm
In a standard multisig, a 2-of-3 wallet requires two signatures regardless of whether you are sending 1 STX to a known friend or 1,000,000 STX to an unverified address. **SentinelVault** changes this. By introducing an AI Oracle, the contract evaluates the "danger" of a transaction before execution.

### Dynamic Scaling
The signature threshold is not a constant; it is a variable function of the risk score. As risk increases, the contract automatically demands higher consensus from the owners. At extreme risk levels, the contract acts as a circuit breaker, halting execution to protect the treasury.

## Security Architecture

SentinelVault is built upon the **Checks-Effects-Interactions** pattern to eliminate re-entrancy risks.

1.  **Checks:** The contract validates the caller's identity, the transaction's existence, its current status (not revoked/executed), and the AI score.
2.  **Effects:** The transaction is marked as `executed: true` in the internal map *before* any assets move.
3.  **Interactions:** The `as-contract` primitive is invoked to perform the `stx-transfer?`, ensuring the contract's own principal is the sender.



---

## Dynamic Risk Scoring

The signature logic is governed by the following tiers within the `execute-tx-with-dynamic-ai-security` function:

| Risk Score ($0-100$) | Logic Category | Required Signatures |
| :--- | :--- | :--- |
| **0 - 40** | Low Risk | Simple Majority ($50\% + 1$) |
| **41 - 70** | Moderate Risk | 2/3 Majority ($66.6\%$) |
| **71 - 90** | High Risk | Full Consensus ($100\%$) |
| **91 - 100** | Extreme Risk | **Blocked** (Threshold > Total Owners) |

---

## Technical Specifications

### Contract State & Constants

The contract maintains a rigorous state to ensure transparency and prevents replay attacks using a global `tx-nonce`.

* **`contract-owner`**: The initial deployer. Holds the unique power to add/remove owners and update the Oracle.
* **`ai-oracle`**: A principal variable pointing to the off-chain AI's on-chain identity.
* **`transactions`**: A complex map storing the submitter, recipient, amount, status flags, risk score, and confirmation count.
* **`tx-confirmations`**: A double-keyed map `{tx-id, owner}` to ensure no owner can vote twice on the same proposal.

---

## API Reference: Private Functions

These functions are internal to the contract logic and cannot be called by external users.

### `is-owner`
* **Input:** `(caller principal)`
* **Logic:** Performs a `map-get?` on the `owners` map.
* **Returns:** A boolean. Used across all public functions to gatekeep access to authorized personnel only.

---

## API Reference: Read-Only Functions

I provide these functions to ensure that any frontend UI or external observer has total visibility into the wallet's state.

### `get-transaction`
Retrieves the full tuple of data for a specific `tx-id`. This includes the amount, the recipient, and whether the AI has scored it yet.

### `has-confirmed`
Checks if a specific principal has already signed a specific transaction. Useful for UI elements to toggle "Confirm" or "Revoke Confirmation" buttons.

### `get-total-owners`
Returns the current count of active owners. This is the denominator for all dynamic threshold calculations.

### `get-tx-nonce`
Returns the ID that will be assigned to the next submitted transaction.

### `get-owner-status`
Returns `true` if the provided principal is an active owner of the vault.

### `get-ai-oracle`
Returns the principal address currently authorized to provide risk scores.

---

## API Reference: Public Administrative Functions

These functions manage the membership and "brain" of the vault.

### `add-owner`
Adds a new principal to the `owners` map and increments the `total-owners` count.
* **Restriction:** Only the `contract-owner` can call this.

### `remove-owner`
Removes a principal from the `owners` map.
* **Restriction:** Only the `contract-owner` can call this.
* **Safety:** Will fail if attempting to remove the last owner (minimum 1 required).

### `update-ai-oracle`
Changes the principal authorized to score transactions. This allows the vault to upgrade its AI logic over time by pointing to a more sophisticated oracle.

---

## API Reference: Transaction Lifecycle

### `submit-tx`
Proposed a new transfer of STX.
* **Action:** Creates a new entry in the `transactions` map and increments the nonce.
* **Requirement:** Caller must be an owner.

### `revoke-tx`
Allows the original submitter to cancel a transaction before it is executed.
* **Action:** Sets the `revoked` flag to true.

### `assign-ai-risk-score`
The AI Oracle calls this to inject its analysis into the contract.
* **Action:** Updates the `risk-score` field.
* **Restriction:** Only the designated `ai-oracle` principal.

### `confirm-tx`
An owner signs a proposed transaction.
* **Action:** Increments `confirmations` and records the individual signature.

### `revoke-confirmation`
An owner withdraws their signature.
* **Action:** Decrements `confirmations`.

### `execute-tx-with-dynamic-ai-security`
The flagship function. It calculates the required threshold based on the `risk-score` and executes the transfer if signatures are sufficient.

---

## Error Code Reference

The contract uses standard unsigned integers for error handling:

| Code | Constant | Meaning |
| :--- | :--- | :--- |
| **u100** | `err-owner-only` | Unauthorized: Caller is not a registered owner. |
| **u101** | `err-oracle-only` | Unauthorized: Caller is not the AI Oracle. |
| **u102** | `err-tx-not-found` | The requested Transaction ID does not exist. |
| **u103** | `err-already-executed` | Transaction has already been successfully sent. |
| **u104** | `err-already-confirmed` | Owner has already signed this transaction. |
| **u105** | `err-insufficient-sigs` | Current signatures do not meet the AI-calculated threshold. |
| **u106** | `err-ai-blocked` | AI risk score is too high (u91+); execution is prohibited. |
| **u107** | `err-unscored` | AI has not yet assigned a risk score to this transaction. |
| **u111** | `err-min-owners-reached` | Cannot remove owner; at least one owner must remain. |

---

## Contribution Guidelines

I welcome improvements to the SentinelVault architecture. To contribute:
1.  Fork the repository.
2.  Create a feature branch for your security enhancement.
3.  Ensure all Clarity unit tests pass.
4.  Submit a Pull Request with a detailed description of the logic changes.

---

## License

MIT License

Copyright (c) 2026 SentinelVault Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---
