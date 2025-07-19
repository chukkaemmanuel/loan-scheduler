# Loan Scheduler Smart Contract

A time-locked smart contract for structured loan payments built on the Stacks blockchain using Clarity. This contract enables automated loan management with scheduled payments and time-based fund releases.

## Overview

The Loan Scheduler contract facilitates peer-to-peer lending with structured payment schedules. It uses Stacks block height for time-locking mechanisms, ensuring payments can only be made when due, and provides security features for both lenders and borrowers.

## Features

### Core Functionality
- **Structured Loan Creation**: Define loan terms including amount, payment size, and intervals
- **Time-Locked Payments**: Payments can only be made when scheduled (based on block height)
- **Automated Loan Tracking**: Automatic calculation of remaining balance and payment schedules
- **Payment History**: Complete record of all payments made
- **Emergency Protection**: Default protection for lenders with emergency withdrawal options

### Security Features
- Role-based authorization (borrower vs lender permissions)
- Input validation and overflow protection
- Emergency withdrawal only after significant default (2+ payment intervals overdue)
- Contract balance protection

## Contract Structure

### Data Storage
- **Loans Map**: Stores all loan details including terms, progress, and status
- **Payment History Map**: Records individual payment transactions
- **Loan Counter**: Unique ID generator for loans

### Key Parameters
- `total-amount`: Total loan amount in STX
- `payment-amount`: Fixed payment amount per interval
- `payment-interval`: Time between payments (in blocks)
- `borrower`: Principal receiving the loan
- `lender`: Principal providing the loan

## Functions

### Public Functions

#### `create-loan`
```clarity
(create-loan borrower total-amount payment-amount payment-interval)
```
Creates a new loan with specified parameters. The lender must transfer the full loan amount to the contract.

**Parameters:**
- `borrower` (principal): Address of the loan recipient
- `total-amount` (uint): Total loan amount in STX
- `payment-amount` (uint): Amount per payment in STX
- `payment-interval` (uint): Blocks between payments

**Returns:** Loan ID (uint)

#### `release-loan-funds`
```clarity
(release-loan-funds loan-id)
```
Releases the loan amount to the borrower. Can only be called by the lender.

**Parameters:**
- `loan-id` (uint): Unique loan identifier

#### `make-payment`
```clarity
(make-payment loan-id)
```
Makes a scheduled payment. Can only be called by the borrower when payment is due.

**Parameters:**
- `loan-id` (uint): Unique loan identifier

**Returns:** Payment details and loan completion status

#### `emergency-withdrawal`
```clarity
(emergency-withdrawal loan-id)
```
Allows lender to withdraw remaining funds after borrower default (2+ payment intervals overdue).

**Parameters:**
- `loan-id` (uint): Unique loan identifier

### Read-Only Functions

#### `get-loan-status`
```clarity
(get-loan-status loan-id)
```
Returns comprehensive loan information including payment status and overdue status.

#### `is-payment-due`
```clarity
(is-payment-due loan-id)
```
Checks if a payment is currently due for the specified loan.

#### `get-loan`
```clarity
(get-loan loan-id)
```
Retrieves basic loan information.

#### `get-payment-history`
```clarity
(get-payment-history loan-id payment-number)
```
Gets details of a specific payment.

## Usage Example

### 1. Create a Loan
```clarity
;; Lender creates a loan for 1000 STX with 100 STX payments every 144 blocks (~24 hours)
(contract-call? .loan-scheduler create-loan 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u1000000000 u100000000 u144)
```

### 2. Release Funds to Borrower
```clarity
;; Lender releases funds (loan-id 1)
(contract-call? .loan-scheduler release-loan-funds u1)
```

### 3. Make a Payment
```clarity
;; Borrower makes payment when due
(contract-call? .loan-scheduler make-payment u1)
```

### 4. Check Loan Status
```clarity
;; Anyone can check loan status
(contract-call? .loan-scheduler get-loan-status u1)
```

## Time-Lock Mechanism

The contract uses Stacks block height for time-locking:
- **Payment Intervals**: Measured in blocks (approximately 10 minutes per block)
- **Common Intervals**:
  - Daily payments: ~144 blocks
  - Weekly payments: ~1008 blocks  
  - Monthly payments: ~4320 blocks

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u400 | ERR-INVALID-AMOUNT | Invalid amount provided |
| u401 | ERR-NOT-AUTHORIZED | Unauthorized access attempt |
| u402 | ERR-INSUFFICIENT-BALANCE | Insufficient balance for operation |
| u403 | ERR-PAYMENT-NOT-DUE | Payment not yet due |
| u404 | ERR-LOAN-NOT-FOUND | Loan does not exist |
| u409 | ERR-LOAN-ALREADY-EXISTS | Loan already exists |
| u410 | ERR-LOAN-COMPLETED | Loan already completed |

## Security Considerations

### For Lenders
- Always verify borrower's identity and creditworthiness off-chain
- Monitor payment schedules and use emergency withdrawal if necessary
- Consider the risk of STX price volatility

### For Borrowers
- Ensure you can meet the payment schedule before accepting a loan
- Make payments promptly to avoid default and potential emergency withdrawal
- Understand that late payments (2+ intervals) may trigger emergency withdrawal

### Smart Contract Security
- All functions include proper authorization checks
- Input validation prevents invalid loan parameters
- Emergency withdrawal requires significant default period
- No external dependencies or oracle risks

## Deployment

### Prerequisites
- Stacks wallet with STX for deployment
- Clarity development environment
- Basic understanding of Stacks blockchain

### Deployment Steps
1. Compile the contract using Clarinet or similar tools
2. Deploy to Stacks testnet for testing
3. Thoroughly test all functions
4. Deploy to mainnet with appropriate testing

### Testing Recommendations
- Test all edge cases (final payments, emergency withdrawals)
- Verify time-lock mechanisms work correctly
- Test with different payment intervals and amounts
- Validate error handling for all error conditions