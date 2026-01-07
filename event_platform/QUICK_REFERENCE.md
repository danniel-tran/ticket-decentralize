# Event Platform Quick Reference

## Module Overview

| Module | File | Purpose | Dependencies |
|--------|------|---------|--------------|
| Access Control | access_control.move | Capability-based permissions | None |
| Users | users.move | Identity & reputation | None |
| Payments | payments.move | Treasury & payment processing | None |
| Events | events.move | Event lifecycle | access_control, users, payments |
| Tickets | tickets.move | NFT ticketing | events, users, payments, access_control |
| Attendance | attendance.move | Soulbound proof NFTs | tickets, events, access_control |

## Key Functions by User Role

### Event Organizer

1. **Create Event:**
   ```move
   events::create_event(
       registry: &mut EventRegistry,
       user_profile: &mut UserProfile,
       badge_registry: &mut BadgeRegistry,
       metadata: EventMetadata,
       config: EventConfig,
   ) -> (EventOrganizerCap, EventTreasury)
   ```

2. **Publish Event:**
   ```move
   events::publish_event(
       event: &mut Event,
       cap: &EventOrganizerCap,
   )
   ```

3. **Grant Validator:**
   ```move
   access_control::grant_validator_cap(
       event_id: ID,
       validator: address,
       organizer_cap: &EventOrganizerCap,
       expires_at: Option<u64>,
   ) -> ValidatorCap
   ```

4. **Withdraw Funds:**
   ```move
   payments::withdraw_funds(
       treasury: &mut EventTreasury,
       amount: u64,
   )
   ```

### Event Attendee

1. **Create Profile:**
   ```move
   users::create_profile(
       display_name: Option<String>,
       zklogin_sub: Option<String>,
   ) -> UserProfile
   ```

2. **Buy Ticket:**
   ```move
   tickets::mint_ticket(
       pool: &mut TicketPool,
       event: &mut Event,
       user_profile: &mut UserProfile,
       event_treasury: &mut EventTreasury,
       platform_treasury: &mut PlatformTreasury,
       registry: &EventRegistry,
       payment: Coin<SUI>,
       tier: String,
       encrypted_data: vector<u8>,
       seal_key_id: String,
       qr_code_hash: vector<u8>,
   ) -> Ticket
   ```

3. **Transfer Ticket:**
   ```move
   tickets::transfer_ticket(
       ticket: Ticket,
       event: &mut Event,
       sender_profile: &mut UserProfile,
       recipient: address,
   )
   ```

4. **Request Refund:**
   ```move
   tickets::refund_ticket(
       ticket: Ticket,
       event: &mut Event,
       pool: &mut TicketPool,
       event_treasury: &mut EventTreasury,
   )
   ```

### Validator

1. **Validate Ticket:**
   ```move
   tickets::validate_ticket(
       ticket: &mut Ticket,
       event: &mut Event,
       user_profile: &mut UserProfile,
       badge_registry: &mut BadgeRegistry,
       validator_cap: &ValidatorCap,
       provided_qr_hash: vector<u8>,
   )
   ```

2. **Mint Attendance Proof:**
   ```move
   attendance::mint_attendance_proof(
       registry: &mut AttendanceRegistry,
       ticket: &Ticket,
       event: &Event,
       validator_cap: &ValidatorCap,
       badge_image_url: String,
       event_title: String,
       event_date: u64,
       verification_hash: vector<u8>,
       location_hash: vector<u8>,
       special_notes: Option<String>,
   ) -> AttendanceProof
   ```

## Object Types & Ownership

| Object | Abilities | Ownership | Shared? |
|--------|-----------|-----------|---------|
| EventOrganizerCap | key, store | Organizer | No |
| ValidatorCap | key, store | Validator | No |
| UserProfile | key | User | No |
| AchievementBadge | key, store | User | No |
| Event | key | None | Yes ✅ |
| EventRegistry | key | None | Yes ✅ |
| EventTreasury | key | None | Yes ✅ |
| PlatformTreasury | key | None | Yes ✅ |
| TicketPool | key | None | Yes ✅ |
| Ticket | key, store | Ticket holder | No |
| AttendanceProof | key | Attendee (Soulbound) | No |
| AttendanceRegistry | key | None | Yes ✅ |

## State Transitions

### Event Lifecycle
```
DRAFT (0) → OPEN (1) → IN_PROGRESS (2) → COMPLETED (3)
    ↓
CANCELLED (4)
```

### Ticket Lifecycle
```
Minted → Validated → Attendance Proof
   ↓
Transferred (if allowed)
   ↓
Refunded (if before deadline & not validated)
```

## Time Constraints

```
Event Creation:
├─ start_time > now
├─ end_time > start_time
├─ registration_deadline <= start_time
└─ refund_deadline <= start_time

Ticket Purchase:
└─ now <= registration_deadline

Refund:
└─ now <= refund_deadline

Event Start:
└─ now >= start_time

Event Complete:
└─ now >= end_time
```

## Payment Flow

```
Ticket Price: 100 SUI
      ↓
    Split
      ↓
├─ Platform Fee: 2.5 SUI → PlatformTreasury
└─ Organizer: 97.5 SUI → EventTreasury (locked for refunds)
      ↓
After refund_deadline
      ↓
Organizer can withdraw unlocked funds
```

## Reputation System

### Score Changes
```
Starting Score: 500/1000

Positive:
+10 → Event created
+5  → Event attended

Negative:
-10 → No-show
-20 → Event cancelled
```

### Rating System
```
Organizer Rating: Weighted average of ratings (0-100)
Attendee Rating: Weighted average of ratings (0-100)

Verified Organizer: rating >= 80 && count >= 5
```

## Achievement Badges

| Badge | Milestone | Rarity |
|-------|-----------|--------|
| First Timer | 1 event attended | Common (0) |
| Event Enthusiast | 10 events attended | Rare (1) |
| Event Legend | 50 events attended | Epic (2) |
| Century Club | 100 events attended | Legendary (3) |
| Rising Organizer | 5 events created | Rare (1) |
| Veteran Organizer | 25 events created | Epic (2) |

## Error Code Ranges

```
1000-1999: access_control
2000-2999: users
3000-3999: events
4000-4999: tickets
5000-5999: attendance
6000-6999: payments
```

## Common Patterns

### Creating an Event
```typescript
1. create_event() → returns (cap, treasury)
2. transfer cap to organizer
3. share treasury
4. publish_event()
```

### Buying a Ticket
```typescript
1. Verify event is open
2. Split payment from gas
3. mint_ticket() → returns ticket
4. Transfer ticket to buyer
```

### Check-in Flow
```typescript
1. validate_ticket() → updates ticket
2. mint_attendance_proof() → returns proof
3. Transfer proof to attendee (soulbound)
```

## Security Checklist

- [ ] All capabilities verify expiration
- [ ] All user operations verify profile ownership
- [ ] All event operations verify event ID match
- [ ] All payment amounts verified exactly
- [ ] All refunds check conditions BEFORE consuming ticket
- [ ] All state updates happen before external calls
- [ ] All events emitted for state changes

## Integration Points

### Walrus (Decentralized Storage)
- Store: Full event details, images, encrypted venue data
- On-chain: Only blob_id references

### Seal (Encryption)
- Store: Encrypted venue access details
- On-chain: Only key_id references

### ZkLogin (Identity)
- Store: OAuth authentication
- On-chain: Only sub (subject identifier) references

## View Functions

All modules provide getter functions:
```move
// Events
events::get_status(event: &Event): u8
events::is_open(event: &Event): bool
events::can_register(event: &Event, ctx: &TxContext): bool

// Tickets
tickets::is_validated(ticket: &Ticket): bool
tickets::get_ticket_number(ticket: &Ticket): u64

// Users
users::get_reputation_score(profile: &UserProfile): u64
users::is_verified_organizer(profile: &UserProfile): bool

// Payments
payments::get_withdrawable_amount(treasury: &EventTreasury): u64
payments::get_locked_for_refunds(treasury: &EventTreasury): u64
```

## Testing Commands

```bash
# Build
sui move build

# Test
sui move test

# Publish (testnet)
sui client publish --gas-budget 100000000

# Publish (mainnet)
sui client publish --gas-budget 100000000 --network mainnet
```

---

## Common Issues & Solutions

**Issue:** "Capability expired"
- **Solution:** Check expires_at timestamp, create new capability

**Issue:** "Registration closed"
- **Solution:** Check if now <= registration_deadline and event is OPEN

**Issue:** "Insufficient balance" on refund
- **Solution:** Ensure treasury has funds (edge case: all funds withdrawn)

**Issue:** "Ticket not transferable"
- **Solution:** Check event.config.is_transferable

**Issue:** "Already has proof"
- **Solution:** One attendance proof per ticket (by design)

---

## Best Practices

1. **Always update UserProfile:** Call package functions when user state changes
2. **Check object IDs:** Verify event_id, ticket_id match across objects
3. **Validate before consuming:** Check all conditions before destructuring objects
4. **Use exact payments:** No overpayment handling, must be exact
5. **Lock refund amounts:** Keep funds locked until refund deadline passes
6. **Emit comprehensive events:** Frontend needs events for indexing
7. **Take references when possible:** batch_mint_attendance uses &Ticket not Ticket

---

This quick reference should help developers integrate with the Event Platform smart contracts efficiently!
