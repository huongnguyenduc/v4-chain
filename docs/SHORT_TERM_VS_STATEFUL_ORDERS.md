# Short-Term vs Stateful Orders in dYdX v4

## Table of Contents

1. [Overview](#overview)
2. [ABCI++ Lifecycle Overview](#abci-lifecycle-overview)
3. [Short-Term Orders (GTB)](#short-term-orders-gtb)
4. [Stateful Orders (GTBT)](#stateful-orders-gtbt)
5. [Technical Architecture](#technical-architecture)
6. [Visibility and Lifecycle](#visibility-and-lifecycle)
7. [When to Use Each Type](#when-to-use-each-type)
8. [Comparison Table](#comparison-table)
9. [Code Examples](#code-examples)
10. [Best Practices](#best-practices)

---

## Overview

dYdX v4 supports two primary order types that serve different trading needs:

- **Short-Term Orders (GTB - Good-Til-Block)**: Fast, ephemeral orders optimized for immediate execution
- **Stateful Orders (GTBT - Good-Til-Block-Time)**: Persistent orders stored on-chain for long-term trading strategies

The choice between these order types depends on your trading strategy, time horizon, and need for immediate vs guaranteed execution.

---

## ABCI++ Lifecycle Overview

Understanding the ABCI++ (Application Blockchain Interface++) lifecycle is crucial for understanding how orders are processed in dYdX v4. ABCI++ is the interface between CometBFT (consensus layer) and the Cosmos SDK application (dYdX protocol).

### What is ABCI++?

ABCI++ extends the original ABCI with new methods that give the application more control over block construction and validation. This is essential for dYdX's high-performance order matching system.

### Transaction Flow in Cosmos/CometBFT

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRANSACTION SUBMISSION                        │
└─────────────────────────────────────────────────────────────────┘

User submits transaction
        ↓
Broadcast via Tendermint P2P
        ↓
┌─────────────────────────────────────────────────────────────────┐
│                    CHECKTX PHASE                                 │
│                    (All Validators)                              │
└─────────────────────────────────────────────────────────────────┘

1. CheckTx
   ├─ Validates transaction (stateless + stateful)
   ├─ For short-term orders: Places in memclob, adds to operations queue
   ├─ For stateful orders: Writes to uncommitted state
   ├─ Returns: Accept/Reject
   └─ Note: Can be called multiple times (ReCheckTx)

┌─────────────────────────────────────────────────────────────────┐
│                    CONSENSUS PHASE                               │
└─────────────────────────────────────────────────────────────────┘

2. PrepareProposal (Proposer Only)
   ├─ Proposer builds block proposal
   ├─ For short-term orders: Gets operations from memclob
   ├─ For stateful orders: Includes transaction in block
   ├─ Creates ProposedOperations transaction
   └─ Returns: Block proposal with transactions

3. ProcessProposal (All Validators)
   ├─ All validators validate the proposed block
   ├─ Decode and validate all transactions
   ├─ Check proposed operations are valid
   └─ Returns: Accept/Reject

4. FinalizeBlock (All Validators - if proposal accepted)
   ├─ Execute all transactions in order
   ├─ DeliverTx for each transaction
   │  ├─ For short-term orders: ProcessProposerOperations (matches)
   │  ├─ For stateful orders: Write to committed state
   │  └─ Update all module state
   └─ Returns: Block execution results

┌─────────────────────────────────────────────────────────────────┐
│                    POST-BLOCK PHASE                              │
└─────────────────────────────────────────────────────────────────┘

5. BeginBlock (All Validators)
   ├─ Initialize block state
   ├─ Process block-level events
   └─ Module BeginBlockers run

6. EndBlock (All Validators)
   ├─ Prune expired orders
   ├─ Trigger conditional orders
   └─ Module EndBlockers run

7. Commit (All Validators)
   ├─ Commit state changes
   ├─ Generate app hash
   └─ Persist to disk

8. Precommit (All Validators)
   ├─ Process staged finalize block events
   └─ Send indexer events

9. PrepareCheckState (All Validators)
   ├─ Replay short-term orders from operations queue
   ├─ Place stateful orders from last block
   ├─ Purge invalid memclob state
   └─ Prepare memclob for next block's CheckTx
```

### Key ABCI++ Methods

#### 1. CheckTx
**Purpose**: Fast validation before consensus  
**Called by**: All validators  
**Frequency**: Once per transaction (can be re-checked)

```go
CheckTx(tx) → Accept/Reject
```

**What happens:**
- Validates transaction (signatures, format, basic checks)
- **Short-term orders**: Places in memclob, adds to operations queue
- **Stateful orders**: Writes to uncommitted state
- Returns immediately (non-blocking)

#### 2. PrepareProposal
**Purpose**: Build block proposal  
**Called by**: Proposer only  
**Frequency**: Once per block

```go
PrepareProposal(req) → ResponsePrepareProposal
```

**What happens:**
- Proposer gets operations from their memclob
- Includes matches, short-term order placements
- Includes stateful order transactions
- Allocates block space (75% for orders, 25% for other txs)

#### 3. ProcessProposal
**Purpose**: Validate proposed block  
**Called by**: All validators  
**Frequency**: Once per block

```go
ProcessProposal(req) → Accept/Reject
```

**What happens:**
- Validators validate the proposed block
- Decode all transactions
- Validate proposed operations
- Can reject invalid proposals

#### 4. FinalizeBlock
**Purpose**: Execute all transactions  
**Called by**: All validators  
**Frequency**: Once per block (if proposal accepted)

```go
FinalizeBlock(req) → ResponseFinalizeBlock
```

**What happens:**
- Executes all transactions in order
- For short-term orders: `ProcessProposerOperations()` (matches)
- For stateful orders: Write to committed state
- Updates all module state

#### 5. PrepareCheckState
**Purpose**: Prepare for next block  
**Called by**: All validators  
**Frequency**: Once per block (after commit)

```go
PrepareCheckState(ctx)
```

**What happens:**
- Replays short-term orders from operations queue
- Places stateful orders from last block onto memclob
- Purges expired/filled orders
- Prepares memclob for next block's CheckTx

### Order Processing in ABCI++ Context

#### Short-Term Orders Flow

```
CheckTx
  ├─ Place in memclob ✅
  ├─ Add to operations queue ✅
  └─ Send off-chain updates ✅

PrepareProposal (Proposer)
  ├─ Get operations from memclob
  └─ Create ProposedOperations tx

FinalizeBlock
  └─ ProcessProposerOperations (execute matches)

PrepareCheckState
  ├─ Replay operations queue
  └─ Purge expired orders
```

#### Stateful Orders Flow

```
CheckTx
  └─ Write to uncommitted state ✅

PrepareProposal (Proposer)
  └─ Include transaction in block

FinalizeBlock
  └─ Write to committed state ✅

PrepareCheckState
  └─ Place on memclob ✅
```

### Differences from Original ABCI

| Feature | ABCI | ABCI++ |
|---------|------|--------|
| **Block Building** | Tendermint decides | App decides (PrepareProposal) |
| **Proposal Validation** | None | ProcessProposal validates |
| **Transaction Order** | Tendermint decides | App controls in PrepareProposal |
| **Vote Extensions** | No | Yes (ExtendVote/VerifyVoteExtension) |
| **Execution** | BeginBlock + DeliverTx + EndBlock | FinalizeBlock (unified) |

### Benefits for dYdX

1. **App-Controlled Block Building**: Proposer can include order matches and operations
2. **Proposal Validation**: Validators verify operations before execution
3. **Optimized Ordering**: Prioritize order operations (75% of bytes)
4. **Fast CheckTx**: In-memory matching without consensus
5. **Efficient Replay**: PrepareCheckState rebuilds memclob from state

### Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    ABCI++ LIFECYCLE                         │
└─────────────────────────────────────────────────────────────┘

User Transaction
        ↓
┌──────────────────┐
│   CheckTx        │  ← All validators validate
│   (All)          │     - Short-term: memclob
└──────────────────┘     - Stateful: uncommitted state
        ↓
┌──────────────────┐
│ PrepareProposal  │  ← Proposer builds block
│   (Proposer)     │     - Gets operations from memclob
└──────────────────┘     - Includes transactions
        ↓
┌──────────────────┐
│ ProcessProposal  │  ← All validators validate
│   (All)          │     - Check operations valid
└──────────────────┘
        ↓
┌──────────────────┐
│ FinalizeBlock    │  ← Execute block
│   (All)          │     - Process matches
└──────────────────┘     - Write state
        ↓
┌──────────────────┐
│ BeginBlock       │  ← Initialize block
│   (All)          │
└──────────────────┘
        ↓
┌──────────────────┐
│ EndBlock         │  ← Cleanup
│   (All)          │     - Prune expired
└──────────────────┘
        ↓
┌──────────────────┐
│ Commit           │  ← Persist state
│   (All)          │
└──────────────────┘
        ↓
┌──────────────────┐
│ PrepareCheckState│  ← Prepare next block
│   (All)          │     - Replay orders
└──────────────────┘     - Place stateful orders
```

---

## Short-Term Orders (GTB)

### Definition

Short-term orders are **ephemeral orders** that expire after approximately **20 blocks** (~1-2 minutes). They are stored **in-memory** in the validator's memclob and are optimized for fast execution and immediate visibility.

### Key Characteristics

| Property | Value |
|----------|-------|
| **Expiration** | ~20 blocks (~1-2 minutes) |
| **Storage** | In-memory (memclob) |
| **Visibility** | Immediate (`BEST_EFFORT_OPENED`) |
| **Transaction Handling** | Excluded from mempool |
| **Persistence** | Ephemeral (lost if not filled) |
| **Order Flags** | `OrderIdFlags_ShortTerm = 0` |

### Technical Details

#### 1. Order Structure

```go
Order {
    OrderId: {
        OrderFlags: OrderIdFlags_ShortTerm,  // 0
        // ... other fields
    },
    GoodTilOneof: {
        GoodTilBlock: uint32,  // Block height when order expires
    },
    // ... other fields
}
```

#### 2. Lifecycle

```
User Submits Order Transaction
        ↓
┌──────────────────────────────────────┐
│ Broadcast via Tendermint P2P         │
│ - Transaction sent to ALL validators │
│ - Each validator receives it         │
└──────────────────────────────────────┘
        ↓
┌──────────────────────────────────────┐
│ CheckTx (All Validators)             │
│ - Validates order                    │
│ - Places in LOCAL memclob            │
│   (Each validator has its own copy)  │
│ - Adds to LOCAL operations queue     │
│ - Sends off-chain updates            │
│   (BEST_EFFORT_OPENED status)        │
│ - ❌ Excluded from mempool           │
└──────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ PrepareProposal (Proposer Only)     │
│ ⚠️ CRITICAL: Only proposer can      │
│    include operations from THEIR    │
│    memclob                          │
│ - Gets operations from memclob      │
│ - Creates ProposedOperations tx     │
│ - Includes matches + placements     │
│ - ❌ Original tx NOT in block       │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ Block Contains:                     │
│ - ProposedOperations (matches)      │
│ - Other transactions                │
│ - ❌ Original order tx NOT included │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ PrepareCheckState (All Validators)  │
│ - Replays local operations queue    │
│ - Purges expired/filled orders      │
│ - Prepares for next block           │
└─────────────────────────────────────┘

⚠️ RISK: If NO validator that received the order
         becomes proposer within ~20 blocks,
         the order expires and is lost!
```

#### 3. Visibility

- **Immediate**: Users see orders via Indexer API with `BEST_EFFORT_OPENED` status
- **Broadcast to All Validators**: Transaction is broadcast via Tendermint P2P to all validators
- **Local Memclob**: Each validator places the order in their LOCAL memclob
- **After Block**: Status changes to `OPENED` when confirmed in block

#### 4. Storage

- **In-Memory Only**: Stored in validator's memclob (not on-chain)
- **Not Persisted**: Lost if validator restarts before block inclusion
- **Operations Queue**: Matches and placements tracked in operations queue

#### 5. ⚠️ Important: Proposer Dependency

**Critical Risk**: Short-term orders depend on a validator becoming proposer (leader) to include them in a block.

**How it works:**
1. Transaction is **broadcast to ALL validators** via Tendermint P2P
2. **ALL validators** process it in `CheckTx` and place order in their LOCAL memclob
3. **ANY validator** that becomes proposer can include operations from their memclob
4. **Risk**: If NO validator that received the order becomes proposer within ~20 blocks, the order expires and is lost

**Example Scenario:**
```
Block 100: User submits short-term order (expires at block 120)
├─ Validator A: Receives order, places in memclob ✅
├─ Validator B: Receives order, places in memclob ✅
├─ Validator C: Receives order, places in memclob ✅
└─ Validator D: Network issue, doesn't receive order ❌

Blocks 101-119: 
├─ Validator E becomes proposer (didn't receive order) ❌
├─ Validator F becomes proposer (didn't receive order) ❌
└─ Validators A, B, C never become proposer ❌

Block 120: Order expires, lost forever ❌
```

**Mitigation in Practice:**
- **Multiple Validators**: With many validators, probability that NONE become proposer in 20 blocks is very low
- **P2P Broadcast**: Tendermint ensures transactions reach most validators
- **Short Expiration**: ~20 blocks (~1-2 minutes) is short enough that most orders get processed
- **Re-submission**: Users can re-submit if order expires

**When to Use Stateful Instead:**
- If guaranteed execution is critical
- If you can't afford order loss
- For long-term positions

### Use Cases

✅ **Best for:**
- Fast execution and immediate trading
- Market making and arbitrage
- High-frequency trading
- Orders that expire quickly
- When immediate visibility is important

❌ **Not suitable for:**
- Long-term positions
- Conditional orders (stop-loss, take-profit)
- Orders that need to persist across validator restarts
- TWAP execution

---

## Stateful Orders (GTBT)

### Definition

Stateful orders are **persistent orders** stored **on-chain** that can last up to **~90-95 days**. They include long-term orders, conditional orders (stop-loss, take-profit), and TWAP orders.

### Key Characteristics

| Property | Value |
|----------|-------|
| **Expiration** | Up to ~90-95 days |
| **Storage** | On-chain state |
| **Visibility** | After block confirmation |
| **Transaction Handling** | Included in mempool and blocks |
| **Persistence** | Long-term (survives restarts) |
| **Order Flags** | `OrderIdFlags_LongTerm = 64`, `OrderIdFlags_Conditional = 32`, `OrderIdFlags_Twap = 128` |

### Types of Stateful Orders

#### 1. Long-Term Orders

Standard persistent orders that remain on the orderbook until filled or expired.

```go
Order {
    OrderId: {
        OrderFlags: OrderIdFlags_LongTerm,  // 64
    },
    GoodTilOneof: {
        GoodTilBlockTime: uint32,  // Unix timestamp
    },
}
```

#### 2. Conditional Orders

Orders that trigger based on price conditions:
- **Stop-Loss**: Triggers when price moves against position
- **Take-Profit**: Triggers when price reaches profit target

```go
Order {
    OrderId: {
        OrderFlags: OrderIdFlags_Conditional,  // 32
    },
    ConditionalOrderTriggerSubticks: uint64,
    ConditionType: CONDITION_TYPE_STOP_LOSS | CONDITION_TYPE_TAKE_PROFIT,
}
```

#### 3. TWAP Orders

Time-Weighted Average Price orders that split large orders over time.

```go
Order {
    OrderId: {
        OrderFlags: OrderIdFlags_Twap,  // 128
    },
    TwapParameters: {
        Duration: uint32,   // Total duration
        Interval: uint32,   // Interval between suborders
    },
}
```

### Technical Details

#### 1. Lifecycle

```
User Submits Order
        ↓
┌─────────────────────────────────────┐
│ CheckTx (All Validators)            │
│ - Validates order                    │
│ - Writes to UNCOMMITTED state       │
│ - ❌ NOT placed on memclob           │
│ - ❌ NO off-chain updates            │
│ - ✅ Included in mempool             │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ PrepareProposal (Proposer)          │
│ - Transaction included in block     │
│ - Like any normal transaction      │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ Block Contains:                     │
│ - ✅ Original order transaction     │
│ - Other transactions                │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ DeliverTx (All Validators)          │
│ - Writes to COMMITTED state         │
│ - Order now in blockchain state     │
│ - Still NOT on memclob              │
└─────────────────────────────────────┘
        ↓
┌─────────────────────────────────────┐
│ PrepareCheckState (All Validators)  │
│ - Places orders from last block     │
│   onto memclob                      │
│ - Sends off-chain updates           │
│   (OPENED status, not BEST_EFFORT)  │
└─────────────────────────────────────┘
```

#### 2. Visibility

- **After Block Confirmation**: Orders only visible after included in block
- **All Validators**: All validators see stateful orders (stored on-chain)
- **Status**: `OPENED` (not `BEST_EFFORT_OPENED`)

#### 3. Storage

- **On-Chain State**: Persisted in blockchain state
- **Survives Restarts**: Orders remain after validator restarts
- **Memclob Placement**: Placed on memclob in `PrepareCheckState` after block commit

### Use Cases

✅ **Best for:**
- Long-term positions (days/weeks)
- Conditional orders (stop-loss, take-profit)
- TWAP execution for large orders
- Orders that need guaranteed persistence
- When you can wait for block confirmation

❌ **Not suitable for:**
- Fast execution requirements
- High-frequency trading
- When immediate visibility is critical
- Very short-term orders

---

## Technical Architecture

### Short-Term Order Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    SHORT-TERM ORDER FLOW                    │
└─────────────────────────────────────────────────────────────┘

1. CheckTx (All Validators)
   ├─ Validate order
   ├─ Place in memclob (in-memory)
   ├─ Add to operations queue
   ├─ Send off-chain updates (BEST_EFFORT_OPENED)
   └─ Exclude from mempool

2. PrepareProposal (Proposer Only)
   ├─ Get operations from memclob
   ├─ Create ProposedOperations transaction
   └─ Include matches + short-term placements

3. ProcessProposal (All Validators)
   ├─ Validate proposed operations
   └─ Accept/Reject proposal

4. FinalizeBlock (All Validators)
   ├─ Execute ProposedOperations
   ├─ Process matches
   └─ Update state

5. PrepareCheckState (All Validators)
   ├─ Replay local operations queue
   ├─ Purge expired/filled orders
   └─ Prepare for next block
```

### Stateful Order Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    STATEFUL ORDER FLOW                      │
└─────────────────────────────────────────────────────────────┘

1. CheckTx (All Validators)
   ├─ Validate order
   ├─ Write to uncommitted state
   └─ Include in mempool

2. PrepareProposal (Proposer)
   ├─ Include transaction in block
   └─ Like normal transaction

3. ProcessProposal (All Validators)
   ├─ Validate transaction
   └─ Accept/Reject proposal

4. FinalizeBlock (All Validators)
   ├─ Execute transaction
   ├─ Write to committed state
   └─ Order now in blockchain

5. PrepareCheckState (All Validators)
   ├─ Place orders from last block on memclob
   ├─ Send off-chain updates (OPENED)
   └─ Order now matchable
```

### Memory vs State Storage

#### Short-Term Orders
```
┌─────────────────┐
│   MemClob       │  ← In-memory orderbook
│   (In-Memory)   │     - Fast access
│                 │     - Lost on restart
│  OperationsQueue│     - Local to validator
└─────────────────┘
```

#### Stateful Orders
```
┌──────────────────┐     ┌────────────────┐
│  Blockchain      │────→│   MemClob      │
│  State           │     │   (In-Memory)  │
│  (On-Chain)      │     │                │
│                  │     │  - Placed in   │
│  - Persistent    │     │    PrepareCheck│
│  - Survives      │     │    State       │
│    restarts      │     │  - For matching│
│  - All validators│     └────────────────┘
│    see it        │
└──────────────────┘
```

---

## Visibility and Lifecycle

### Short-Term Orders

| Phase | Visibility | Status | Notes |
|-------|------------|--------|-------|
| **CheckTx** | ✅ Immediate | `BEST_EFFORT_OPENED` | Only validator that processed it |
| **After Block** | ✅ Confirmed | `OPENED` | All validators see operations |
| **Expiration** | ❌ Removed | `EXPIRED` | After ~20 blocks |

### Stateful Orders

| Phase | Visibility | Status | Notes |
|-------|------------|--------|-------|
| **CheckTx** | ❌ Not visible | N/A | Only in uncommitted state |
| **After Block** | ✅ Visible | `OPENED` | All validators see it |
| **On Memclob** | ✅ Matchable | `OPENED` | After PrepareCheckState |
| **Expiration** | ❌ Removed | `EXPIRED` | After GoodTilBlockTime |

### Off-Chain Updates

#### Short-Term Orders
```go
// Sent immediately in CheckTx
offchainUpdates := types.NewOffchainUpdates()
offchainUpdates.AddPlaceMessage(orderId, message)
// Status: BEST_EFFORT_OPENED
k.sendOffchainMessagesWithTxHash(offchainUpdates, txHash, ...)
```

#### Stateful Orders
```go
// Sent in PrepareCheckState (after block commit)
// Place messages are removed (CondenseMessagesForReplay)
// Only removal/update messages sent
// Status: OPENED (not BEST_EFFORT_OPENED)
```

---

## When to Use Each Type

### Decision Tree

```
Do you need immediate execution?
├─ YES → Short-Term Order
│   └─ Fast, ephemeral, immediate visibility
│
└─ NO → Do you need long-term persistence?
    ├─ YES → Stateful Order
    │   ├─ Long-term position? → Long-Term Order
    │   ├─ Conditional logic? → Conditional Order
    │   └─ TWAP execution? → TWAP Order
    │
    └─ NO → Short-Term Order (default)
```

### Use Case Examples

#### Example 1: Day Trader
```
Scenario: "I want to buy BTC at $50,000, but only if it happens in the next minute"

Solution: Short-Term Order
- Fast execution
- Immediate visibility
- Expires quickly (~20 blocks)
```

#### Example 2: Long-Term Investor
```
Scenario: "I want to sell my ETH position if it reaches $3,000, valid for the next month"

Solution: Stateful Order (Conditional)
- Long expiration (up to 90 days)
- Conditional trigger
- Guaranteed persistence
```

#### Example 3: Market Maker
```
Scenario: "I want to place many limit orders that update frequently"

Solution: Short-Term Orders
- Fast placement
- Immediate feedback
- Low cost (no on-chain storage)
```

#### Example 4: Large Order Execution
```
Scenario: "I want to buy 1000 BTC over the next hour using TWAP"

Solution: Stateful Order (TWAP)
- Time-weighted execution
- Long duration
- Guaranteed execution
```

---

## Comparison Table

| Feature | Short-Term Orders | Stateful Orders |
|---------|------------------|-----------------|
| **Expiration** | ~20 blocks (~1-2 min) | Up to ~90-95 days |
| **Storage** | In-memory (memclob) | On-chain state |
| **Visibility** | Immediate (`BEST_EFFORT_OPENED`) | After block (`OPENED`) |
| **Transaction** | Excluded from mempool | Included in mempool |
| **In Block** | Operations only | Full transaction |
| **Persistence** | Ephemeral | Long-term |
| **Validator Visibility** | Local only | All validators |
| **Cost** | Lower (no on-chain) | Higher (on-chain) |
| **Use Case** | Fast trading, market making | Long-term, conditional, TWAP |
| **Survives Restart** | ❌ No | ✅ Yes |
| **Order Flags** | `0` (ShortTerm) | `32` (Conditional), `64` (LongTerm), `128` (TWAP) |

---

## Code Examples

### Creating a Short-Term Order

```go
// CLI Command
dydxprotocold tx clob place-order \
    owner subaccount_number clientId clobPairId side quantums subticks goodTilBlock

// Go Code
msg := types.NewMsgPlaceOrder(
    types.Order{
        OrderId: types.OrderId{
            ClientId: clientId,
            SubaccountId: satypes.SubaccountId{
                Owner:  owner,
                Number: subaccountNumber,
            },
            ClobPairId: clobPairId,
            OrderFlags: types.OrderIdFlags_ShortTerm,  // Short-term flag
        },
        Side:         types.Order_SIDE_BUY,
        Quantums:     quantums,
        Subticks:     subticks,
        GoodTilOneof: &types.Order_GoodTilBlock{
            GoodTilBlock: goodTilBlock,  // ~20 blocks from now
        },
    },
)
```

### Creating a Stateful Order

```go
// Long-Term Order
msg := types.NewMsgPlaceOrder(
    types.Order{
        OrderId: types.OrderId{
            // ... same fields ...
            OrderFlags: types.OrderIdFlags_LongTerm,  // Long-term flag
        },
        Side: types.Order_SIDE_SELL,
        Quantums: quantums,
        Subticks: subticks,
        GoodTilOneof: &types.Order_GoodTilBlockTime{
            GoodTilBlockTime: goodTilBlockTime,  // Unix timestamp (up to 90 days)
        },
    },
)

// Conditional Order (Stop-Loss)
msg := types.NewMsgPlaceOrder(
    types.Order{
        OrderId: types.OrderId{
            // ... same fields ...
            OrderFlags: types.OrderIdFlags_Conditional,  // Conditional flag
        },
        Side: types.Order_SIDE_SELL,
        Quantums: quantums,
        Subticks: subticks,
        GoodTilOneof: &types.Order_GoodTilBlockTime{
            GoodTilBlockTime: goodTilBlockTime,
        },
        ConditionalOrderTriggerSubticks: triggerPrice,
        ConditionType: types.Order_CONDITION_TYPE_STOP_LOSS,
    },
)
```

### Checking Order Status

```typescript
// Via Indexer API
const orders = await indexerClient.account.getSubaccountOrders(
    subaccountId,
    {
        status: [OrderStatus.OPEN, OrderStatus.BEST_EFFORT_OPENED],
    }
);

// Short-term orders: Can have BEST_EFFORT_OPENED status
// Stateful orders: Only OPEN status (after confirmation)
```

---

## Best Practices

### Short-Term Orders

1. **Use for Fast Execution**
   - Market making
   - Arbitrage
   - Quick trades

2. **Monitor Expiration**
   - Orders expire in ~20 blocks
   - Re-submit if needed

3. **Handle BEST_EFFORT_OPENED**
   - Understand it's optimistic
   - Wait for OPENED status for confirmation

4. **Don't Rely on Persistence**
   - Orders lost on validator restart
   - Use stateful orders if persistence needed

5. **⚠️ Understand Proposer Dependency**
   - Orders require a validator that received them to become proposer
   - Transaction is broadcast to ALL validators, so risk is low
   - But if NO validator that received the order becomes proposer in ~20 blocks, order is lost
   - **Mitigation**: Re-submit if order expires without execution
   - **Alternative**: Use stateful orders if guaranteed execution is critical

### Stateful Orders

1. **Use for Long-Term Strategies**
   - Position management
   - Conditional orders
   - TWAP execution

2. **Set Appropriate Expiration**
   - Up to 90-95 days
   - Don't set too far in future unnecessarily

3. **Understand Visibility Delay**
   - Orders visible after block confirmation
   - Not immediate like short-term

4. **Consider Cost**
   - On-chain storage has cost
   - Use short-term for high-frequency

### General Guidelines

1. **Default to Short-Term**
   - For most regular trading
   - Better UX (immediate feedback)
   - Lower cost

2. **Use Stateful When Needed**
   - Long-term positions
   - Conditional logic required
   - TWAP execution

3. **Monitor Order Status**
   - Check BEST_EFFORT_OPENED → OPENED transition
   - Handle expiration appropriately

4. **Consider Network Conditions**
   - Short-term: Better for high throughput
   - Stateful: Better for guaranteed execution

---

## Additional Resources

- [dYdX v4 Documentation](https://docs.dydx.exchange/)
- [dYdX v4 Technical Architecture](https://dydx.exchange/blog/v4-technical-architecture-overview)
- [CLOB Module Documentation](./protocol/x/clob/README.md)
- [Indexer API Documentation](./indexer/README.md)

---

## Glossary

- **GTB (Good-Til-Block)**: Short-term order expiration based on block height
- **GTBT (Good-Til-Block-Time)**: Stateful order expiration based on Unix timestamp
- **MemClob**: In-memory Central Limit Order Book
- **BEST_EFFORT_OPENED**: Optimistic order status (short-term only)
- **OPENED**: Confirmed order status (both types, after block)
- **Operations Queue**: Queue of order operations (matches, placements) for block proposal
- **PrepareCheckState**: ABCI++ method that prepares memclob for next block

---

*Last Updated: Based on dYdX v4 Chain codebase analysis*
