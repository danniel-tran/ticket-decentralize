# Event Platform - Sui Move Smart Contracts

A comprehensive decentralized event and ticketing platform built on Sui blockchain.

## Module Architecture

### 1. access_control.move
**Purpose:** Manages capabilities and permissions

**Key Structs:**
- `PlatformAdminCap` - Platform admin capability
- `EventOrganizerCap` - Event organizer capability with granular permissions
- `ValidatorCap` - Ticket validator capability for check-ins
- `MultiSigOrganizer` - Multi-signature support for co-organized events

### 2. events.move
**Purpose:** Core event lifecycle management

**Key Structs:**
- `EventRegistry` - Global registry (shared)
- `Event` - Main event object (shared)
- `EventMetadata` - Event details with Walrus blob reference
- `EventConfig` - Event configuration (times, capacity, pricing)
- `EventStats` - Event statistics (copyable)

**Event Statuses:**
- 0: DRAFT
- 1: OPEN (accepting registrations)
- 2: IN_PROGRESS
- 3: COMPLETED
- 4: CANCELLED

### 3. payments.move
**Purpose:** Payment processing and revenue management

**Key Structs:**
- `EventTreasury` - Holds funds per event
- `PlatformTreasury` - Platform fee collection (shared)
- `Payment` - Payment record for history
- `DiscountCode` - Discount codes with usage limits
- `RefundPolicy` - Refund configuration

### 4. tickets.move
**Purpose:** Ticket NFT minting and validation

**Key Structs:**
- `Ticket` - Ticket NFT (owned by user)
- `TicketMetadata` - Contains encrypted data (Seal integration)
- `ValidationInfo` - Check-in validation status
- `TicketPool` - Shared ticket pool per event

### 5. attendance.move
**Purpose:** Attendance proof NFTs

**Key Structs:**
- `AttendanceProof` - Soulbound attendance NFT
- `VerificationData` - Check-in/out timestamps and validation
- `AttendanceMetadata` - Badge image and event details
- `AttendanceRegistry` - Global registry (shared)

### 6. users.move
**Purpose:** User profiles and reputation

**Key Structs:**
- `UserProfile` - User profile (owned)
- `UserIdentity` - ZkLogin integration, social links
- `ReputationData` - Reputation score and ratings
- `UserStats` - Event participation statistics
- `AchievementBadge` - Achievement NFTs

## Integration Flow

### Event Creation
```
1. Organizer calls events::create_event()
2. Receives EventOrganizerCap
3. Creates EventTreasury via payments::create_event_treasury()
4. Creates TicketPool via tickets::create_ticket_pool()
5. Publishes event via events::publish_event()
```

### Ticket Purchase
```
1. User calls tickets::mint_ticket() with payment
2. payments::process_payment() splits funds (organizer + platform fee)
3. events::register_attendee() adds user to event
4. Ticket NFT minted to user's wallet
5. users::add_total_spent() updates user stats
```

### Check-in
```
1. Validator scans QR code
2. Calls tickets::validate_ticket() with ValidatorCap
3. events::check_in_attendee() marks as checked in
4. attendance::mint_attendance_proof() creates proof NFT
5. users::increment_events_attended() updates stats
```

### Refund
```
1. User calls tickets::refund_ticket()
2. Validates refund deadline via events::can_refund()
3. payments::issue_refund() returns funds
4. events::unregister_attendee() removes from event
5. Ticket NFT destroyed
```

## External Integrations

### Walrus Storage
- Event images stored on Walrus
- Reference stored in `EventMetadata.walrus_blob_id`
- Attendance badge images stored on Walrus

### Seal Encryption
- Ticket metadata encrypted with Seal
- Stored in `TicketMetadata.encrypted_data`
- Key ID stored in `TicketMetadata.seal_key_id`

### ZkLogin
- User identity via zklogin
- Stored in `UserIdentity.zklogin_sub`
- Privacy-preserving authentication

## Build & Deploy

### Prerequisites
```bash
# Install Sui CLI
cargo install --locked --git https://github.com/MystenLabs/sui.git --branch mainnet sui
```

### Build
```bash
cd event_platform
sui move build
```

### Test
```bash
sui move test
```

### Deploy to Testnet
```bash
sui client publish --gas-budget 100000000
```

## Key Features

✅ **Modular Architecture** - 6 independent modules with clear responsibilities
✅ **Capability-Based Access Control** - Secure permission system
✅ **Shared Object Optimization** - Efficient concurrent access
✅ **Event-Driven Architecture** - Comprehensive event emission for indexing
✅ **Walrus Integration** - Decentralized image storage
✅ **Seal Integration** - Encrypted ticket data
✅ **ZkLogin Support** - Privacy-preserving identity
✅ **Reputation System** - User reputation and ratings
✅ **Achievement Badges** - Gamification with NFT badges
✅ **Multi-Sig Support** - Co-organized events
✅ **Discount Codes** - Promotional pricing
✅ **Refund System** - Time-based refund policies
✅ **Attendance Proofs** - Soulbound attendance NFTs

## Security Features

- Capability verification on all state changes
- Time-based validation (deadlines, expiry)
- Payment amount validation
- Refund balance checks
- State transition validation
- No-show penalties

## Gas Optimization

- Efficient data structures
- Batch operations for attendance
- Minimal on-chain storage
- Walrus for large data
- Copyable stats structs

## Frontend Integration

Key functions for dApp:
- Event discovery: Query EventRegistry
- User registration: create_profile()
- Ticket purchase: mint_ticket()
- Event management: update_event(), cancel_event()
- Check-in: validate_ticket()
- Analytics: get_event_stats(), get_user_stats()

## Error Codes

All modules use consistent error codes:
- `ENotAuthorized = 1` - Permission denied
- `EInvalidTime = 3` - Invalid timestamp
- Module-specific codes defined in each module

## Next Steps

1. **Testing** - Comprehensive unit and integration tests
2. **Security Audit** - Review all capability flows
3. **Frontend Development** - React dApp with @mysten/dapp-kit
4. **Indexer** - Index on-chain events for queries
5. **Analytics Dashboard** - Event organizer insights

## License

[Your License Here]
