# Event Platform - Entity Relationship Model

## Overview
This document describes the complete entity relationship model for the decentralized event ticketing platform.

---

## Entity Definitions

### **Object Types Legend**
- 🔷 **Owned Object** - Stored in user's wallet
- 🔶 **Shared Object** - Accessible by anyone, shared state
- 🔸 **Store Ability** - Can be transferred/stored in other objects
- 🔒 **Soulbound** - Cannot be transferred (no 'store' ability)

---

## Core Entities

### 1️⃣ **UserProfile** 🔷 (Owned)
```
UserProfile {
    id: UID
    owner: address                    [PK]
    identity: UserIdentity
    reputation: ReputationData
    stats: UserStats
    preferences: UserPreferences
    created_at: u64
    updated_at: u64
}

UserIdentity {
    display_name: Option<String>
    zklogin_sub: Option<String>       [External: OAuth ID]
    zklogin_provider: Option<String>  [External: "google", "facebook"]
    email_hash: Option<vector<u8>>
    avatar_url: Option<String>        [External: Walrus blob_id]
    bio: Option<String>
    social_links: vector<String>
}

ReputationData {
    score: u64                        [0-1000]
    organizer_rating: u64             [0-100]
    attendee_rating: u64              [0-100]
    organizer_rating_count: u64
    attendee_rating_count: u64
    verified_organizer: bool
    badges: vector<ID>                [FK → AchievementBadge]
}

UserStats {
    events_created: u64
    events_attended: u64
    no_show_count: u64
    tickets_purchased: u64
    tickets_transferred: u64
    total_spent: u64
}
```

**Relationships:**
- `1:N` → **AchievementBadge** (owns badges)
- `1:N` → **Event** (creates events as organizer)
- `1:N` → **Ticket** (purchases tickets)
- `1:N` → **AttendanceProof** (receives proofs)

---

### 2️⃣ **Event** 🔶 (Shared)
```
Event {
    id: UID                          [PK]
    organizer: address               [FK → UserProfile.owner]
    metadata: EventMetadata
    config: EventConfig
    stats: EventStats
    status: u8                       [0=DRAFT, 1=OPEN, 2=IN_PROGRESS, 3=COMPLETED, 4=CANCELLED]
    attendees: Table<address, AttendeeInfo>  [FK → UserProfile.owner]
    created_at: u64
    updated_at: u64
}

EventMetadata {
    title: String
    description: String
    walrus_blob_id: String           [External: Walrus storage]
    image_url: String
    category: String                 [Indexed in EventRegistry]
    tags: vector<String>
}

EventConfig {
    start_time: u64
    end_time: u64
    registration_deadline: u64
    capacity: u64
    ticket_price: u64                [In MIST: 1 SUI = 10^9 MIST]
    requires_approval: bool
    is_transferable: bool
    refund_deadline: u64
}

EventStats {
    registered: u64
    attended: u64
    revenue: u64
    refunded: u64
}

AttendeeInfo {
    registered_at: u64
    checked_in: bool
    check_in_time: Option<u64>
}
```

**Relationships:**
- `N:1` → **UserProfile** (organizer)
- `1:1` → **EventTreasury** (event_id FK)
- `1:1` → **TicketPool** (event_id FK)
- `1:N` → **Ticket** (event_id FK)
- `1:N` → **AttendanceProof** (event_id FK)
- `1:N` → **DiscountCode** (event_id FK)
- `N:1` → **EventRegistry** (indexed by category)

---

### 3️⃣ **Ticket** 🔷🔸 (Owned + Store)
```
Ticket {
    id: UID                          [PK]
    event_id: ID                     [FK → Event]
    owner: address                   [FK → UserProfile.owner]
    original_owner: address          [FK → UserProfile.owner]
    metadata: TicketMetadata
    validation: ValidationInfo
    mint_time: u64
}

TicketMetadata {
    ticket_number: u64               [Unique per event]
    tier: String                     ["VIP", "General", "Early Bird"]
    encrypted_data: vector<u8>       [Seal encrypted venue details]
    seal_key_id: String              [External: Seal key reference]
    qr_code_hash: vector<u8>>        [SHA-256 for validation]
}

ValidationInfo {
    is_validated: bool
    validation_time: Option<u64>
    validator_address: Option<address>  [FK → ValidatorCap holder]
}
```

**Relationships:**
- `N:1` → **Event** (event_id)
- `N:1` → **UserProfile** (owner)
- `N:1` → **TicketPool** (counted in pool)
- `1:1` → **AttendanceProof** (one proof per ticket)

---

### 4️⃣ **AttendanceProof** 🔷🔒 (Owned, Soulbound)
```
AttendanceProof {
    id: UID                          [PK]
    event_id: ID                     [FK → Event]
    attendee: address                [FK → UserProfile.owner]
    ticket_id: ID                    [FK → Ticket, Unique]
    verification: VerificationData
    metadata: AttendanceMetadata
}

VerificationData {
    check_in_time: u64
    check_out_time: Option<u64>
    validator_address: address       [FK → ValidatorCap holder]
    verification_hash: vector<u8>
    location_hash: vector<u8>
}

AttendanceMetadata {
    badge_image_url: String          [External: Walrus blob_id]
    event_title: String
    event_date: u64
    special_notes: Option<String>
}
```

**Relationships:**
- `N:1` → **Event** (event_id)
- `N:1` → **UserProfile** (attendee)
- `1:1` → **Ticket** (ticket_id, unique constraint)
- `N:1` → **AttendanceRegistry** (tracked for duplicates)

---

### 5️⃣ **AchievementBadge** 🔷🔸 (Owned + Store)
```
AchievementBadge {
    id: UID                          [PK]
    user: address                    [FK → UserProfile.owner]
    badge_type: String               ["first_timer", "event_enthusiast", etc.]
    name: String
    description: String
    metadata_url: String             [External: Walrus blob_id]
    earned_at: u64
    rarity: u8                       [0=Common, 1=Rare, 2=Epic, 3=Legendary]
}
```

**Relationships:**
- `N:1` → **UserProfile** (user)
- `N:1` → **BadgeRegistry** (tracked)

---

## Capability Entities

### 6️⃣ **EventOrganizerCap** 🔷🔸 (Owned + Store)
```
EventOrganizerCap {
    id: UID                          [PK]
    event_id: ID                     [FK → Event]
    permissions: OrganizerPermissions
    granted_at: u64
    expires_at: Option<u64>
}

OrganizerPermissions {
    can_update_event: bool
    can_cancel_event: bool
    can_approve_registrations: bool
    can_withdraw_funds: bool
    can_grant_validators: bool
}
```

**Relationships:**
- `1:1` → **Event** (one primary cap per event)
- `1:N` → **EventOrganizerCap** (can delegate limited caps)

---

### 7️⃣ **ValidatorCap** 🔷🔸 (Owned + Store)
```
ValidatorCap {
    id: UID                          [PK]
    event_id: ID                     [FK → Event]
    validator_address: address
    granted_by: address              [FK → EventOrganizerCap holder]
    granted_at: u64
    expires_at: Option<u64>
}
```

**Relationships:**
- `N:1` → **Event** (multiple validators per event)
- `N:1` → **EventOrganizerCap** (granted by organizer)

---

## Registry Entities

### 8️⃣ **EventRegistry** 🔶 (Shared)
```
EventRegistry {
    id: UID                          [PK, Singleton]
    total_events: u64
    platform_fee_percent: u64        [Fixed: 250 = 2.5%]
    events_by_category: Table<String, vector<ID>>  [Index: category → event_ids]
}
```

**Relationships:**
- `1:N` → **Event** (indexes all events by category)

---

### 9️⃣ **BadgeRegistry** 🔶 (Shared)
```
BadgeRegistry {
    id: UID                          [PK, Singleton]
    total_badges: u64
    badges_by_user: Table<address, vector<ID>>  [Index: user → badge_ids]
}
```

**Relationships:**
- `1:N` → **AchievementBadge** (tracks all badges)

---

### 🔟 **AttendanceRegistry** 🔶 (Shared)
```
AttendanceRegistry {
    id: UID                          [PK, Singleton]
    total_proofs: u64
    proofs_by_ticket: Table<ID, ID>  [Unique: ticket_id → proof_id]
}
```

**Relationships:**
- `1:N` → **AttendanceProof** (prevents duplicate proofs)

---

## Financial Entities

### 1️⃣1️⃣ **EventTreasury** 🔶 (Shared)
```
EventTreasury {
    id: UID                          [PK]
    event_id: ID                     [FK → Event, Unique]
    organizer: address               [FK → UserProfile.owner]
    balance: Balance<SUI>
    platform_fee: u64                [Usually 250 = 2.5%]
    total_collected: u64
    total_withdrawn: u64
    locked_for_refunds: u64          [Reserved for potential refunds]
}
```

**Relationships:**
- `1:1` → **Event** (event_id, unique)
- `N:1` → **UserProfile** (organizer)

---

### 1️⃣2️⃣ **PlatformTreasury** 🔶 (Shared)
```
PlatformTreasury {
    id: UID                          [PK, Singleton]
    balance: Balance<SUI>            [Accumulates platform fees]
    total_fees_collected: u64
    total_withdrawn: u64             [Always 0 - no withdrawal!]
}
```

**Relationships:**
- None (singleton, no withdrawals)

---

### 1️⃣3️⃣ **TicketPool** 🔶 (Shared)
```
TicketPool {
    id: UID                          [PK]
    event_id: ID                     [FK → Event, Unique]
    total_minted: u64
    available: u64                   [capacity - total_minted]
}
```

**Relationships:**
- `1:1` → **Event** (event_id, unique)
- `1:N` → **Ticket** (tracks capacity)

---

### 1️⃣4️⃣ **DiscountCode** 🔷🔸 (Owned + Store)
```
DiscountCode {
    id: UID                          [PK]
    code: String
    event_id: ID                     [FK → Event]
    discount_percent: u64            [0-100]
    max_uses: u64
    current_uses: u64
    expiry: u64
}
```

**Relationships:**
- `N:1` → **Event** (event_id)

---

## Complete Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    PLATFORM REGISTRIES (Singletons)             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │EventRegistry │    │BadgeRegistry │    │AttendanceReg │    │
│  │   (Shared)   │    │   (Shared)   │    │   (Shared)   │    │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    │
│         │                   │                     │             │
│         │ indexes           │ tracks              │ prevents    │
│         │ by category       │ badges              │ duplicates  │
└─────────┼───────────────────┼─────────────────────┼─────────────┘
          │                   │                     │
          ↓                   ↓                     ↓

┌─────────────────────────────────────────────────────────────────┐
│                         USER DOMAIN                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         1:N                              │
│  │  UserProfile     │◄────────────┬───────────────────┐        │
│  │    (Owned)       │             │                   │        │
│  ├──────────────────┤             ↓                   ↓        │
│  │ • owner [PK]     │    ┌─────────────────┐  ┌──────────────┐│
│  │ • reputation     │    │AchievementBadge │  │TicketOwned   ││
│  │ • stats          │    │  (Owned+Store)  │  │(Multiple)    ││
│  │ • badges: [ID]   │    └─────────────────┘  └──────────────┘│
│  └────────┬─────────┘                                          │
│           │                                                     │
│           │ 1:N creates                                        │
│           │                                                     │
└───────────┼─────────────────────────────────────────────────────┘
            ↓

┌─────────────────────────────────────────────────────────────────┐
│                         EVENT DOMAIN                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────┐          │
│  │               Event (Shared)                     │          │
│  ├──────────────────────────────────────────────────┤          │
│  │ • id [PK]                                        │          │
│  │ • organizer [FK→UserProfile]                    │          │
│  │ • status: 0-4                                    │          │
│  │ • attendees: Table<address, AttendeeInfo>       │          │
│  └────┬──────────┬──────────┬──────────┬───────────┘          │
│       │          │          │          │                       │
│       │ 1:1      │ 1:1      │ 1:N      │ 1:N                  │
│       ↓          ↓          ↓          ↓                       │
│  ┌─────────┐ ┌──────────┐ ┌────────┐ ┌──────────────┐        │
│  │Treasury │ │TicketPool│ │Ticket  │ │DiscountCode  │        │
│  │(Shared) │ │ (Shared) │ │(Owned) │ │(Owned+Store) │        │
│  └─────────┘ └──────────┘ └───┬────┘ └──────────────┘        │
│                                │                               │
│                                │ 1:1                           │
└────────────────────────────────┼───────────────────────────────┘
                                 ↓

┌─────────────────────────────────────────────────────────────────┐
│                     ATTENDANCE DOMAIN                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────┐                      │
│  │    AttendanceProof (Soulbound)       │                      │
│  ├──────────────────────────────────────┤                      │
│  │ • id [PK]                            │                      │
│  │ • event_id [FK→Event]                │                      │
│  │ • attendee [FK→UserProfile]          │                      │
│  │ • ticket_id [FK→Ticket, UNIQUE]      │                      │
│  │ • verification_hash                  │                      │
│  └──────────────────────────────────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     CAPABILITY DOMAIN                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────┐         1:N delegates                  │
│  │EventOrganizerCap   │◄─────────────────┐                    │
│  │  (Owned+Store)     │                  │                    │
│  ├────────────────────┤                  │                    │
│  │ • event_id [FK]    │                  │                    │
│  │ • permissions      │                  │                    │
│  │ • expires_at       │                  │                    │
│  └────────┬───────────┘                  │                    │
│           │                               │                    │
│           │ 1:N grants                    │                    │
│           ↓                               │                    │
│  ┌────────────────────┐                  │                    │
│  │  ValidatorCap      │──────────────────┘                    │
│  │  (Owned+Store)     │                                       │
│  ├────────────────────┤                                       │
│  │ • event_id [FK]    │                                       │
│  │ • validator        │                                       │
│  │ • expires_at       │                                       │
│  └────────────────────┘                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     FINANCIAL DOMAIN                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐          Split Payment                    │
│  │ Ticket Purchase │                                           │
│  │   (100 SUI)     │                                           │
│  └────────┬────────┘                                           │
│           │                                                     │
│           ├──► 97.5 SUI ──► EventTreasury (Shared, 1:1 Event) │
│           │                  • locked_for_refunds              │
│           │                  • withdrawable by organizer       │
│           │                                                     │
│           └──► 2.5 SUI  ──► PlatformTreasury (Shared, Singleton)│
│                              • NO withdrawal                    │
│                              • Accumulates forever              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Constraints & Rules

### Unique Constraints
1. **UserProfile.owner** - One profile per address
2. **EventTreasury.event_id** - One treasury per event
3. **TicketPool.event_id** - One pool per event
4. **AttendanceProof.ticket_id** - One proof per ticket
5. **EventRegistry** - Singleton
6. **PlatformTreasury** - Singleton
7. **BadgeRegistry** - Singleton
8. **AttendanceRegistry** - Singleton

### Foreign Key Relationships
```
UserProfile.owner ← Event.organizer
UserProfile.owner ← Ticket.owner
UserProfile.owner ← AttendanceProof.attendee
UserProfile.owner ← AchievementBadge.user

Event.id ← Ticket.event_id
Event.id ← EventTreasury.event_id
Event.id ← TicketPool.event_id
Event.id ← AttendanceProof.event_id
Event.id ← DiscountCode.event_id
Event.id ← EventOrganizerCap.event_id
Event.id ← ValidatorCap.event_id

Ticket.id ← AttendanceProof.ticket_id (UNIQUE)
```

### Referential Integrity Rules
1. **Cascade Delete**: Not applicable (blockchain immutability)
2. **Restrict Delete**: Objects cannot be deleted, only marked inactive
3. **Foreign Key Verification**: All FK checks done via assertions in Move

### Business Rules
1. **Event Status Flow**: DRAFT → OPEN → IN_PROGRESS → COMPLETED (or CANCELLED)
2. **Ticket Lifecycle**: Minted → [Transferred*] → Validated → Proof Minted
3. **Refund Window**: Can only refund if `now <= refund_deadline && !validated`
4. **Capacity**: `TicketPool.available = Event.capacity - TicketPool.total_minted`
5. **Platform Fee**: Fixed at 2.5%, split on every ticket purchase
6. **Soulbound**: AttendanceProof cannot be transferred (no 'store' ability)

---

## Data Flow Examples

### Example 1: Create Event
```
1. UserProfile (organizer)
   ↓ creates
2. Event (DRAFT status)
   ├─► EventTreasury (balance: 0)
   ├─► TicketPool (available: capacity)
   └─► EventOrganizerCap (full permissions)
3. EventRegistry.total_events++
4. EventRegistry.events_by_category[category].push(event_id)
5. UserProfile.stats.events_created++
```

### Example 2: Buy Ticket
```
1. User sends: 100 SUI
   ↓ splits
2. Platform: 2.5 SUI → PlatformTreasury
   Organizer: 97.5 SUI → EventTreasury
3. EventTreasury.locked_for_refunds += 97.5 SUI
4. Event.stats.registered++
5. Event.attendees[user] = AttendeeInfo
6. TicketPool.total_minted++
7. TicketPool.available--
8. Ticket NFT → User
9. UserProfile.stats.tickets_purchased++
10. UserProfile.stats.total_spent += 100 SUI
```

### Example 3: Check-in & Proof
```
1. Validator validates Ticket
   ↓ verifies QR hash
2. Ticket.validation.is_validated = true
3. Event.attendees[user].checked_in = true
4. Event.stats.attended++
5. UserProfile.stats.events_attended++
6. UserProfile.reputation.score += 5
7. AttendanceProof → User (soulbound)
8. AttendanceRegistry.proofs_by_ticket[ticket_id] = proof_id
9. Check milestones → Maybe AchievementBadge
```

---

## Cardinality Summary

| Relationship | From | To | Type | Notes |
|--------------|------|-----|------|-------|
| User → Events | UserProfile | Event | 1:N | As organizer |
| User → Tickets | UserProfile | Ticket | 1:N | As owner |
| User → Badges | UserProfile | AchievementBadge | 1:N | Earned |
| User → Proofs | UserProfile | AttendanceProof | 1:N | Received |
| Event → Treasury | Event | EventTreasury | 1:1 | Unique |
| Event → Pool | Event | TicketPool | 1:1 | Unique |
| Event → Tickets | Event | Ticket | 1:N | Issued |
| Event → Proofs | Event | AttendanceProof | 1:N | Minted |
| Event → Discounts | Event | DiscountCode | 1:N | Created |
| Event → OrgCap | Event | EventOrganizerCap | 1:1 | Primary |
| OrgCap → OrgCap | EventOrganizerCap | EventOrganizerCap | 1:N | Delegates |
| OrgCap → ValCap | EventOrganizerCap | ValidatorCap | 1:N | Grants |
| Ticket → Proof | Ticket | AttendanceProof | 1:1 | Unique |
| Registry → Events | EventRegistry | Event | 1:N | Indexes |
| Registry → Badges | BadgeRegistry | AchievementBadge | 1:N | Tracks |
| Registry → Proofs | AttendanceRegistry | AttendanceProof | 1:N | Prevents dups |

---

## External References (Not Stored On-Chain)

| Field | Entity | External System | Purpose |
|-------|--------|-----------------|---------|
| `walrus_blob_id` | EventMetadata | Walrus | Full event details |
| `seal_key_id` | TicketMetadata | Seal | Decryption key for venue |
| `encrypted_data` | TicketMetadata | Seal | Encrypted venue access |
| `zklogin_sub` | UserIdentity | OAuth Provider | User identifier |
| `avatar_url` | UserIdentity | Walrus | Profile image |
| `badge_image_url` | AttendanceMetadata | Walrus | Badge artwork |

---

This ER model provides the complete structure for the decentralized event platform with all entities, relationships, and constraints clearly defined.
