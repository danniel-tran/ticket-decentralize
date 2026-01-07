# Event Platform Smart Contract Implementation

## Overview

This is a complete implementation of a decentralized event and ticketing platform on Sui blockchain using Move language. The platform enables event organizers to create and manage events, users to purchase NFT tickets with encrypted access details, validators to check-in attendees, and automatic reputation tracking with proof-of-attendance NFTs.

## Architecture

The platform consists of 6 interconnected modules built in dependency order:

```
Layer 1: access_control.move  (Security foundation)
Layer 2: users.move           (Identity & reputation)
Layer 3: events.move          (Core business entity)
Layer 4: tickets.move         (NFT ticketing)
Layer 5: attendance.move      (Proof system)
Layer 6: payments.move        (Financial operations)
```

## Module Details

### 1. access_control.move (Layer 1)
**Purpose:** Capability-based permission system for all platform operations

**Key Features:**
- ✅ PlatformAdminCap for platform-wide administration
- ✅ EventOrganizerCap with granular permissions
- ✅ ValidatorCap for attendee check-ins
- ✅ Expiration support for all capabilities
- ✅ Delegation support with limited permissions
- ✅ All verification functions assert (abort on failure)

**Capabilities:**
```move
EventOrganizerCap {
    can_update_event: bool,
    can_cancel_event: bool,
    can_approve_registrations: bool,
    can_withdraw_funds: bool,
    can_grant_validators: bool,
}
```

**Security:** All capabilities check expiration automatically when verified.

---

### 2. users.move (Layer 2)
**Purpose:** User identity, reputation, and achievement system

**Key Features:**
- ✅ UserProfile as owned object (in user wallet)
- ✅ ZkLogin integration support (OAuth sub references)
- ✅ Dynamic reputation scoring (0-1000)
- ✅ Weighted average ratings for organizers and attendees
- ✅ Automatic badge minting at milestones
- ✅ Achievement rarity system (Common/Rare/Epic/Legendary)

**Reputation Algorithm:**
```
Starting: 500/1000
+10 per event created
+5 per event attended
-10 per no-show
-20 per cancelled event
```

**Achievement Milestones:**
```
Attendance Badges:
- 1 event   → "First Timer" (Common)
- 10 events → "Event Enthusiast" (Rare)
- 50 events → "Event Legend" (Epic)
- 100 events → "Century Club" (Legendary)

Organizer Badges:
- 5 events  → "Rising Organizer" (Rare)
- 25 events → "Veteran Organizer" (Epic)
```

**Integration:** All modules that modify user state MUST call package functions to update stats and reputation.

---

### 3. events.move (Layer 3)
**Purpose:** Core event entity and lifecycle management

**Key Features:**
- ✅ Event as shared object for concurrent access
- ✅ State machine with 5 states (DRAFT/OPEN/IN_PROGRESS/COMPLETED/CANCELLED)
- ✅ Attendee tracking with check-in status
- ✅ Category-based indexing for discovery
- ✅ Comprehensive time validation
- ✅ Revenue and capacity tracking

**Event Lifecycle:**
```
DRAFT → publish_event() → OPEN
  ↓                         ↓
cancel_event()    start_event() → IN_PROGRESS
  ↓                                ↓
CANCELLED              complete_event() → COMPLETED
```

**Validation:**
- start_time > now
- end_time > start_time
- registration_deadline <= start_time
- refund_deadline <= start_time
- capacity > 0

**Integration:** create_event() returns (EventOrganizerCap, EventTreasury) which must be shared/transferred by the caller.

---

### 4. tickets.move (Layer 4)
**Purpose:** NFT ticketing with encrypted metadata and validation

**Key Features:**
- ✅ Ticket as owned NFT (in user wallet)
- ✅ Encrypted venue details (Seal key_id references)
- ✅ QR code hash verification
- ✅ Ticket transfers with restrictions
- ✅ Refund system with all security checks
- ✅ Ticket pool for capacity management

**Security Highlights:**
```move
// CRITICAL: Refund checks ALL conditions before consuming ticket
refund_ticket() {
    // 1. Verify ownership
    // 2. Verify event match
    // 3. Verify refund window open
    // 4. Verify not validated
    // 5. Verify treasury has funds
    // 6. THEN process refund
}
```

**Payment Flow:**
1. User calls mint_ticket with SUI payment
2. Payment split: organizer amount + platform fee
3. Attendee registered in event
4. UserProfile stats updated
5. Ticket NFT created and returned

---

### 5. attendance.move (Layer 5)
**Purpose:** Soulbound attendance proof NFTs

**Key Features:**
- ✅ AttendanceProof is soulbound (no 'store' ability)
- ✅ Prevents duplicate proofs per ticket
- ✅ Batch minting support
- ✅ Check-in and check-out tracking
- ✅ Validator verification
- ✅ Metadata with Walrus blob references

**Important:**
```move
// CRITICAL: Take tickets by reference, not value!
batch_mint_attendance(tickets: vector<&Ticket>, ...)
```

**Proof Data:**
- Check-in time
- Optional check-out time
- Validator address
- Verification hash
- Location hash
- Event metadata

---

### 6. payments.move (Layer 6)
**Purpose:** Payment processing, treasury management, revenue splitting

**Key Features:**
- ✅ EventTreasury as shared object per event
- ✅ PlatformTreasury for fee collection
- ✅ Automatic payment splitting (organizer + platform fee)
- ✅ Locked funds for refunds
- ✅ Discount code system
- ✅ Withdrawal restrictions (can't withdraw locked funds)

**Financial Model:**
```
Default platform fee: 2.5% (250/10000)

Ticket Price = 100 SUI
├─ Platform Fee = 2.5 SUI (locked in PlatformTreasury)
└─ Organizer Amount = 97.5 SUI (locked until refund deadline)
```

**Refund Protection:**
- Funds locked for refunds until refund_deadline
- Organizer can only withdraw (total_balance - locked_amount)
- Ensures refunds always succeed if within deadline

---

## Integration Examples

### Complete Event Creation Flow

```typescript
// Frontend TypeScript example
const txb = new TransactionBlock();

// 1. Create user profile (if not exists)
const profile = txb.moveCall({
  target: `${PACKAGE}::users::create_profile`,
  arguments: [
    txb.pure("Alice"),
    txb.pure(null),
  ],
});

// 2. Create event
const metadata = {
  title: "Sui Developer Conference",
  description: "Annual developer conference",
  walrus_blob_id: "blob_xyz123",
  image_url: "https://walrus.site/image.png",
  category: "Tech",
  tags: ["blockchain", "sui", "move"],
};

const config = {
  start_time: Date.now() + 86400000, // Tomorrow
  end_time: Date.now() + 172800000,  // 2 days from now
  registration_deadline: Date.now() + 82800000,
  capacity: 1000,
  ticket_price: 10_000_000_000, // 10 SUI in MIST
  requires_approval: false,
  is_transferable: true,
  refund_deadline: Date.now() + 79200000,
};

const [cap, treasury] = txb.moveCall({
  target: `${PACKAGE}::events::create_event`,
  arguments: [
    registry,
    profile,
    badgeRegistry,
    txb.pure(metadata),
    txb.pure(config),
  ],
});

// 3. Transfer cap to organizer
txb.transferObjects([cap], organizer);

// 4. Share treasury
txb.moveCall({
  target: '0x2::transfer::share_object',
  arguments: [treasury],
  typeArguments: [`${PACKAGE}::payments::EventTreasury`],
});

// 5. Execute transaction
await client.signAndExecuteTransactionBlock({ ... });
```

### Ticket Purchase Flow

```typescript
const txb = new TransactionBlock();

// 1. Split payment from gas coin
const payment = txb.splitCoins(txb.gas, [ticketPrice]);

// 2. Mint ticket
const ticket = txb.moveCall({
  target: `${PACKAGE}::tickets::mint_ticket`,
  arguments: [
    pool,
    event,
    profile,
    eventTreasury,
    platformTreasury,
    eventRegistry,
    payment,
    txb.pure("VIP"),
    txb.pure(encryptedData),
    txb.pure(sealKeyId),
    txb.pure(qrCodeHash),
  ],
});

// 3. Transfer ticket to buyer
txb.transferObjects([ticket], buyer);
```

### Check-in and Proof Minting

```typescript
// Step 1: Validate ticket
const txb1 = new TransactionBlock();
txb1.moveCall({
  target: `${PACKAGE}::tickets::validate_ticket`,
  arguments: [
    ticket,
    event,
    userProfile,
    badgeRegistry,
    validatorCap,
    txb1.pure(qrCodeHash),
  ],
});

// Step 2: Mint attendance proof
const txb2 = new TransactionBlock();
const proof = txb2.moveCall({
  target: `${PACKAGE}::attendance::mint_attendance_proof`,
  arguments: [
    attendanceRegistry,
    ticket,
    event,
    validatorCap,
    txb2.pure(badgeImageUrl),
    txb2.pure(eventTitle),
    txb2.pure(eventDate),
    txb2.pure(verificationHash),
    txb2.pure(locationHash),
    txb2.pure(specialNotes),
  ],
});

txb2.transferObjects([proof], attendee);
```

---

## Security Features

### Capability Expiration
All capabilities support optional expiration:
```move
create_limited_cap(
    original_cap,
    permissions,
    option::some(expiry_timestamp),
    ctx
)
```

### Refund Safety
```move
// Checks BEFORE consuming ticket:
1. Ownership verification
2. Event ID match
3. Refund window open
4. Not already validated
5. Treasury has sufficient balance
```

### Payment Atomicity
```move
// Payment is atomic - all or nothing:
1. Verify exact payment
2. Split coin (platform + organizer)
3. Deposit to both treasuries
4. Update all stats
5. Create ticket
```

### Reentrancy Protection
Following Checks-Effects-Interactions pattern:
1. ✅ All assertions first
2. ✅ Update state
3. ✅ External calls (transfers) last

---

## Event Emission

All state changes emit events for indexing:

```move
EventCreated { event_id, organizer, title, category, timestamp }
TicketMinted { ticket_id, event_id, owner, ticket_number, tier, price_paid, timestamp }
AttendanceProofMinted { proof_id, event_id, attendee, ticket_id, timestamp }
ReputationUpdated { profile_id, owner, old_score, new_score, timestamp }
PaymentProcessed { event_id, payer, amount, platform_fee, organizer_amount, timestamp }
// ... and many more
```

---

## Error Codes

Each module has its own error code range:

```move
access_control: 1000-1999
users:          2000-2999
events:         3000-3999
tickets:        4000-4999
attendance:     5000-5999
payments:       6000-6999
```

---

## Gas Optimization

1. **Counters over Tables:** Using simple u64 counters where possible
2. **Minimal on-chain storage:** Only blob_id and key_id references
3. **Efficient indexing:** Category-based tables for event discovery
4. **Batch operations:** batch_mint_attendance for multiple proofs

---

## Testing Checklist

### Unit Tests Needed
- [ ] Capability expiration checks
- [ ] Reputation calculations
- [ ] Payment splitting accuracy
- [ ] Refund conditions
- [ ] Ticket transfer restrictions
- [ ] Badge milestone triggers

### Integration Tests Needed
- [ ] Complete event lifecycle
- [ ] User creates event → stats updated
- [ ] User buys ticket → stats + reputation updated
- [ ] Validator checks in → attendance proof minted
- [ ] Organizer withdraws funds
- [ ] User requests refund
- [ ] Ticket transfer flow

### Security Tests Needed
- [ ] All error conditions abort correctly
- [ ] Capability expiration blocks operations
- [ ] Refund after validation fails
- [ ] Withdraw exceeding available funds fails
- [ ] Double proof minting fails

---

## Deployment Steps

1. **Install Sui CLI:**
   ```bash
   cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui
   ```

2. **Build the project:**
   ```bash
   cd event_platform
   sui move build
   ```

3. **Run tests:**
   ```bash
   sui move test
   ```

4. **Deploy to testnet:**
   ```bash
   sui client publish --gas-budget 100000000
   ```

5. **Save deployed addresses:**
   - Package ID
   - EventRegistry ID
   - PlatformTreasury ID
   - BadgeRegistry ID
   - AttendanceRegistry ID

---

## Known Limitations

1. **No on-chain scheduling:** Event state transitions (DRAFT→OPEN, OPEN→IN_PROGRESS) require manual transactions
2. **Fixed platform fee:** Hardcoded to 2.5%, requires upgrade to change
3. **No partial refunds:** Only full ticket refunds supported
4. **No ticket resale:** Transfers are free, no secondary market built-in

---

## Future Enhancements

1. **Dynamic pricing:** Time-based or demand-based ticket pricing
2. **Multi-tier tickets:** Different access levels with different prices
3. **Event series:** Templates and recurring events
4. **Waitlist:** Queue system for sold-out events
5. **Group tickets:** Bulk purchase discounts
6. **Sponsorship:** NFT-based sponsorship tiers

---

## Support & Contributions

For issues or questions:
- GitHub Issues: [Your repo URL]
- Discord: [Your Discord server]
- Documentation: [Your docs site]

---

## License

[Specify your license]

---

## Credits

Built following the Sui Event Platform specification.
Implements best practices from Sui Foundation and Move language standards.
