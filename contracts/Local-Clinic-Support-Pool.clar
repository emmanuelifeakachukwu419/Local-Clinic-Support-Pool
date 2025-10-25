(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_OWNER (err u100))
(define-constant ERR_CLINIC_NOT_FOUND (err u101))
(define-constant ERR_CLINIC_ALREADY_EXISTS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_CLINIC_NOT_ACTIVE (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_VOTING_ENDED (err u107))
(define-constant ERR_NOT_ORACLE (err u108))
(define-constant ERR_INVALID_PERFORMANCE (err u109))
(define-constant ERR_REWARD_ALREADY_CLAIMED (err u110))
(define-constant ERR_INSUFFICIENT_TIER (err u111))
(define-constant ERR_INVALID_AUDIT_QUERY (err u112))
(define-constant ERR_AUDIT_LOG_FULL (err u113))
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u114))
(define-constant ERR_SUBSCRIPTION_ALREADY_EXISTS (err u115))
(define-constant ERR_SUBSCRIPTION_NOT_DUE (err u116))
(define-constant ERR_INVALID_FREQUENCY (err u117))

(define-constant MIN_DONATION u1000000)
(define-constant MIN_PERFORMANCE_SCORE u70)
(define-constant VOTING_PERIOD u144)
(define-constant DISBURSEMENT_INTERVAL u1008)
(define-constant BRONZE_TIER_THRESHOLD u5000000)
(define-constant SILVER_TIER_THRESHOLD u20000000)
(define-constant GOLD_TIER_THRESHOLD u50000000)
(define-constant PLATINUM_TIER_THRESHOLD u100000000)
(define-constant MAX_AUDIT_EVENTS_PER_CLINIC u100)
(define-constant MONTHLY_BLOCKS u4320)
(define-constant QUARTERLY_BLOCKS u12960)
(define-constant SUBSCRIPTION_BONUS_MULTIPLIER u110)

(define-data-var total-pool-balance uint u0)
(define-data-var next-clinic-id uint u1)
(define-data-var oracle-address principal CONTRACT_OWNER)
(define-data-var next-audit-event-id uint u1)
(define-data-var next-subscription-id uint u1)

(define-map clinics
  { clinic-id: uint }
  {
    name: (string-ascii 100),
    address: principal,
    status: (string-ascii 20),
    total-received: uint,
    performance-score: uint,
    last-performance-update: uint,
    registration-block: uint
  }
)

(define-map clinic-votes
  { clinic-id: uint, voter: principal }
  { vote: bool, block-height: uint }
)

(define-map voting-sessions
  { clinic-id: uint }
  {
    proposal-type: (string-ascii 20),
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    is-active: bool
  }
)

(define-map donor-contributions
  { donor: principal }
  { total-donated: uint, last-donation-block: uint }
)

(define-map clinic-performance-history
  { clinic-id: uint, period: uint }
  { score: uint, updated-block: uint }
)

(define-map donor-loyalty-tiers
  { donor: principal }
  {
    tier: (string-ascii 20),
    milestone-rewards-claimed: uint,
    voting-power-multiplier: uint,
    last-tier-update: uint
  }
)

(define-map milestone-rewards
  { donor: principal, milestone: uint }
  { claimed: bool, reward-amount: uint, claim-block: uint }
)

(define-map audit-events
  { event-id: uint }
  {
    clinic-id: uint,
    event-type: (string-ascii 30),
    actor: principal,
    details: (string-ascii 200),
    timestamp: uint,
    block-height: uint,
    additional-data: (optional uint)
  }
)

(define-map clinic-audit-counters
  { clinic-id: uint }
  { event-count: uint, last-event-id: uint }
)

(define-map recurring-subscriptions
  { subscriber: principal }
  {
    subscription-id: uint,
    amount: uint,
    frequency-blocks: uint,
    next-payment-block: uint,
    total-payments: uint,
    is-active: bool,
    start-block: uint
  }
)

(define-public (donate (amount uint))
  (let
    (
      (previous-contribution (default-to { total-donated: u0, last-donation-block: u0 } (map-get? donor-contributions { donor: tx-sender })))
      (new-total (+ amount (get total-donated previous-contribution)))
    )
    (begin
      (asserts! (>= amount MIN_DONATION) ERR_INVALID_AMOUNT)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
      (map-set donor-contributions
        { donor: tx-sender }
        {
          total-donated: new-total,
          last-donation-block: stacks-block-height
        }
      )
      (update-donor-tier tx-sender new-total)
      (ok amount)
    )
  )
)

(define-public (register-clinic (name (string-ascii 100)))
  (let
    (
      (clinic-id (var-get next-clinic-id))
    )
    (asserts! (is-none (map-get? clinics { clinic-id: clinic-id })) ERR_CLINIC_ALREADY_EXISTS)
    (map-set clinics
      { clinic-id: clinic-id }
      {
        name: name,
        address: tx-sender,
        status: "pending",
        total-received: u0,
        performance-score: u0,
        last-performance-update: u0,
        registration-block: stacks-block-height
      }
    )
    (var-set next-clinic-id (+ clinic-id u1))
    (start-voting-session clinic-id "approval")
    (log-audit-event clinic-id "clinic_registered" tx-sender "Clinic registration initiated" (some clinic-id))
    (ok clinic-id)
  )
)

(define-public (vote-on-clinic (clinic-id uint) (vote bool))
  (let
    (
      (voting-session (unwrap! (map-get? voting-sessions { clinic-id: clinic-id }) ERR_CLINIC_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (get is-active voting-session) ERR_VOTING_ENDED)
    (asserts! (<= current-block (get end-block voting-session)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? clinic-votes { clinic-id: clinic-id, voter: tx-sender })) ERR_ALREADY_VOTED)
    
    (let
    (
      (voting-power (get-voting-power tx-sender))
      )
      (map-set clinic-votes
        { clinic-id: clinic-id, voter: tx-sender }
      { vote: vote, block-height: current-block }
    )
    
    (map-set voting-sessions
    { clinic-id: clinic-id }
    (merge voting-session
        {
            yes-votes: (if vote (+ (get yes-votes voting-session) voting-power) (get yes-votes voting-session)),
            no-votes: (if vote (get no-votes voting-session) (+ (get no-votes voting-session) voting-power))
          }
        )
      )
      (ok vote)
    )
  )
)

(define-public (finalize-voting (clinic-id uint))
  (let
    (
      (voting-session (unwrap! (map-get? voting-sessions { clinic-id: clinic-id }) ERR_CLINIC_NOT_FOUND))
      (clinic-data (unwrap! (map-get? clinics { clinic-id: clinic-id }) ERR_CLINIC_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (get is-active voting-session) ERR_VOTING_ENDED)
    (asserts! (> current-block (get end-block voting-session)) ERR_VOTING_ENDED)
    
    (let
      (
        (approved (> (get yes-votes voting-session) (get no-votes voting-session)))
        (new-status (if approved "active" "rejected"))
      )
      (map-set clinics
        { clinic-id: clinic-id }
        (merge clinic-data { status: new-status })
      )
      
      (map-set voting-sessions
        { clinic-id: clinic-id }
        (merge voting-session { is-active: false })
      )
      (log-audit-event clinic-id "voting_finalized" tx-sender (if approved "Clinic approved by community vote" "Clinic rejected by community vote") (some (if approved u1 u0)))
      (ok approved)
    )
  )
)

(define-public (update-clinic-performance (clinic-id uint) (score uint))
  (let
    (
      (clinic-data (unwrap! (map-get? clinics { clinic-id: clinic-id }) ERR_CLINIC_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (var-get oracle-address)) ERR_NOT_ORACLE)
    (asserts! (<= score u100) ERR_INVALID_PERFORMANCE)
    (asserts! (is-eq (get status clinic-data) "active") ERR_CLINIC_NOT_ACTIVE)
    
    (map-set clinics
      { clinic-id: clinic-id }
      (merge clinic-data
        {
          performance-score: score,
          last-performance-update: stacks-block-height
        }
      )
    )
    
    (map-set clinic-performance-history
      { clinic-id: clinic-id, period: (/ stacks-block-height DISBURSEMENT_INTERVAL) }
      { score: score, updated-block: stacks-block-height }
    )
    (log-audit-event clinic-id "performance_updated" tx-sender "Performance score updated by oracle" (some score))
    (ok score)
  )
)

(define-public (disburse-funds (clinic-id uint))
  (let
    (
      (clinic-data (unwrap! (map-get? clinics { clinic-id: clinic-id }) ERR_CLINIC_NOT_FOUND))
      (pool-balance (var-get total-pool-balance))
      (performance-score (get performance-score clinic-data))
    )
    (asserts! (is-eq (get status clinic-data) "active") ERR_CLINIC_NOT_ACTIVE)
    (asserts! (>= performance-score MIN_PERFORMANCE_SCORE) ERR_INVALID_PERFORMANCE)
    
    (let
      (
        (disbursement-amount (/ (* pool-balance performance-score) u10000))
      )
      (asserts! (> disbursement-amount u0) ERR_INSUFFICIENT_FUNDS)
      (asserts! (<= disbursement-amount pool-balance) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? disbursement-amount tx-sender (get address clinic-data))))
      (var-set total-pool-balance (- pool-balance disbursement-amount))
      
      (map-set clinics
        { clinic-id: clinic-id }
        (merge clinic-data
          { total-received: (+ (get total-received clinic-data) disbursement-amount) }
        )
      )
      (log-audit-event clinic-id "funds_disbursed" tx-sender "Funds disbursed to clinic" (some disbursement-amount))
      (ok disbursement-amount)
    )
  )
)

(define-public (remove-clinic (clinic-id uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_OWNER)
    (asserts! (is-some (map-get? clinics { clinic-id: clinic-id })) ERR_CLINIC_NOT_FOUND)
    (start-voting-session clinic-id "removal")
    (ok true)
  )
)

(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_OWNER)
    (var-set oracle-address new-oracle)
    (ok new-oracle)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_OWNER)
    (asserts! (<= amount (var-get total-pool-balance)) ERR_INSUFFICIENT_FUNDS)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (var-set total-pool-balance (- (var-get total-pool-balance) amount))
    (ok amount)
  )
)

(define-public (setup-recurring-donation (amount uint) (frequency (string-ascii 10)))
  (let
    (
      (existing-sub (map-get? recurring-subscriptions { subscriber: tx-sender }))
      (frequency-blocks (if (is-eq frequency "monthly") MONTHLY_BLOCKS (if (is-eq frequency "quarterly") QUARTERLY_BLOCKS u0)))
      (subscription-id (var-get next-subscription-id))
    )
    (asserts! (is-none existing-sub) ERR_SUBSCRIPTION_ALREADY_EXISTS)
    (asserts! (>= amount MIN_DONATION) ERR_INVALID_AMOUNT)
    (asserts! (> frequency-blocks u0) ERR_INVALID_FREQUENCY)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
    
    (let
      (
        (previous-contribution (default-to { total-donated: u0, last-donation-block: u0 } (map-get? donor-contributions { donor: tx-sender })))
        (bonus-amount (/ (* amount SUBSCRIPTION_BONUS_MULTIPLIER) u100))
        (new-total (+ bonus-amount (get total-donated previous-contribution)))
      )
      (map-set donor-contributions
        { donor: tx-sender }
        {
          total-donated: new-total,
          last-donation-block: stacks-block-height
        }
      )
      (update-donor-tier tx-sender new-total)
    )
    
    (map-set recurring-subscriptions
      { subscriber: tx-sender }
      {
        subscription-id: subscription-id,
        amount: amount,
        frequency-blocks: frequency-blocks,
        next-payment-block: (+ stacks-block-height frequency-blocks),
        total-payments: u1,
        is-active: true,
        start-block: stacks-block-height
      }
    )
    (var-set next-subscription-id (+ subscription-id u1))
    (ok subscription-id)
  )
)

(define-public (process-recurring-donation)
  (let
    (
      (subscription (unwrap! (map-get? recurring-subscriptions { subscriber: tx-sender }) ERR_SUBSCRIPTION_NOT_FOUND))
    )
    (asserts! (get is-active subscription) ERR_SUBSCRIPTION_NOT_FOUND)
    (asserts! (>= stacks-block-height (get next-payment-block subscription)) ERR_SUBSCRIPTION_NOT_DUE)
    
    (let
      (
        (amount (get amount subscription))
      )
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
      
      (let
        (
          (previous-contribution (default-to { total-donated: u0, last-donation-block: u0 } (map-get? donor-contributions { donor: tx-sender })))
          (bonus-amount (/ (* amount SUBSCRIPTION_BONUS_MULTIPLIER) u100))
          (new-total (+ bonus-amount (get total-donated previous-contribution)))
        )
        (map-set donor-contributions
          { donor: tx-sender }
          {
            total-donated: new-total,
            last-donation-block: stacks-block-height
          }
        )
        (update-donor-tier tx-sender new-total)
      )
      
      (map-set recurring-subscriptions
        { subscriber: tx-sender }
        (merge subscription
          {
            next-payment-block: (+ stacks-block-height (get frequency-blocks subscription)),
            total-payments: (+ (get total-payments subscription) u1)
          }
        )
      )
      (ok amount)
    )
  )
)

(define-public (cancel-recurring-donation)
  (let
    (
      (subscription (unwrap! (map-get? recurring-subscriptions { subscriber: tx-sender }) ERR_SUBSCRIPTION_NOT_FOUND))
    )
    (asserts! (get is-active subscription) ERR_SUBSCRIPTION_NOT_FOUND)
    (map-set recurring-subscriptions
      { subscriber: tx-sender }
      (merge subscription { is-active: false })
    )
    (ok true)
  )
)

(define-public (claim-milestone-reward (milestone uint))
  (let
    (
      (donor-stats (unwrap! (map-get? donor-contributions { donor: tx-sender }) ERR_CLINIC_NOT_FOUND))
      (reward-key { donor: tx-sender, milestone: milestone })
      (existing-reward (map-get? milestone-rewards reward-key))
    )
    (asserts! (is-none existing-reward) ERR_REWARD_ALREADY_CLAIMED)
    (let
      (
        (total-donated (get total-donated donor-stats))
        (reward-amount (calculate-milestone-reward milestone total-donated))
      )
      (asserts! (> reward-amount u0) ERR_INSUFFICIENT_TIER)
      (asserts! (<= reward-amount (var-get total-pool-balance)) ERR_INSUFFICIENT_FUNDS)
      
      (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))
      (var-set total-pool-balance (- (var-get total-pool-balance) reward-amount))
      
      (map-set milestone-rewards
        reward-key
        {
          claimed: true,
          reward-amount: reward-amount,
          claim-block: stacks-block-height
        }
      )
      (ok reward-amount)
    )
  )
)

(define-private (update-donor-tier (donor principal) (total-donated uint))
  (let
    (
      (current-tier (get-donor-tier-name total-donated))
      (voting-multiplier (get-tier-voting-multiplier total-donated))
    )
    (map-set donor-loyalty-tiers
      { donor: donor }
      {
        tier: current-tier,
        milestone-rewards-claimed: (get milestone-rewards-claimed (default-to { tier: "basic", milestone-rewards-claimed: u0, voting-power-multiplier: u1, last-tier-update: u0 } (map-get? donor-loyalty-tiers { donor: donor }))),
        voting-power-multiplier: voting-multiplier,
        last-tier-update: stacks-block-height
      }
    )
    true
  )
)

(define-private (calculate-milestone-reward (milestone uint) (total-donated uint))
  (if (is-eq milestone u1)
    (if (>= total-donated BRONZE_TIER_THRESHOLD) u100000 u0)
    (if (is-eq milestone u2)
      (if (>= total-donated SILVER_TIER_THRESHOLD) u250000 u0)
      (if (is-eq milestone u3)
        (if (>= total-donated GOLD_TIER_THRESHOLD) u500000 u0)
        (if (is-eq milestone u4)
          (if (>= total-donated PLATINUM_TIER_THRESHOLD) u1000000 u0)
          u0
        )
      )
    )
  )
)

(define-private (get-donor-tier-name (total-donated uint))
  (if (>= total-donated PLATINUM_TIER_THRESHOLD)
    "platinum"
    (if (>= total-donated GOLD_TIER_THRESHOLD)
      "gold"
      (if (>= total-donated SILVER_TIER_THRESHOLD)
        "silver"
        (if (>= total-donated BRONZE_TIER_THRESHOLD)
          "bronze"
          "basic"
        )
      )
    )
  )
)

(define-private (get-tier-voting-multiplier (total-donated uint))
  (if (>= total-donated PLATINUM_TIER_THRESHOLD)
    u5
    (if (>= total-donated GOLD_TIER_THRESHOLD)
      u4
      (if (>= total-donated SILVER_TIER_THRESHOLD)
        u3
        (if (>= total-donated BRONZE_TIER_THRESHOLD)
          u2
          u1
        )
      )
    )
  )
)

(define-private (get-voting-power (voter principal))
  (let
    (
      (tier-info (map-get? donor-loyalty-tiers { donor: voter }))
    )
    (match tier-info
      tier-data (get voting-power-multiplier tier-data)
      u1
    )
  )
)

(define-private (start-voting-session (clinic-id uint) (proposal-type (string-ascii 20)))
  (begin
    (map-set voting-sessions
      { clinic-id: clinic-id }
      {
        proposal-type: proposal-type,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height VOTING_PERIOD),
        yes-votes: u0,
        no-votes: u0,
        is-active: true
      }
    )
    true
  )
)

(define-private (log-audit-event (clinic-id uint) (event-type (string-ascii 30)) (actor principal) (details (string-ascii 200)) (additional-data (optional uint)))
  (let
    (
      (event-id (var-get next-audit-event-id))
      (current-counter (default-to { event-count: u0, last-event-id: u0 } (map-get? clinic-audit-counters { clinic-id: clinic-id })))
      (new-event-count (+ (get event-count current-counter) u1))
    )
    (if (<= new-event-count MAX_AUDIT_EVENTS_PER_CLINIC)
      (begin
        (map-set audit-events
          { event-id: event-id }
          {
            clinic-id: clinic-id,
            event-type: event-type,
            actor: actor,
            details: details,
            timestamp: stacks-block-height,
            block-height: stacks-block-height,
            additional-data: additional-data
          }
        )
        (map-set clinic-audit-counters
          { clinic-id: clinic-id }
          {
            event-count: new-event-count,
            last-event-id: event-id
          }
        )
        (var-set next-audit-event-id (+ event-id u1))
        true
      )
      false
    )
  )
)

(define-read-only (get-clinic-details (clinic-id uint))
  (map-get? clinics { clinic-id: clinic-id })
)

(define-read-only (get-voting-session (clinic-id uint))
  (map-get? voting-sessions { clinic-id: clinic-id })
)

(define-read-only (get-pool-balance)
  (var-get total-pool-balance)
)

(define-read-only (get-donor-stats (donor principal))
  (map-get? donor-contributions { donor: donor })
)

(define-read-only (get-clinic-performance (clinic-id uint) (period uint))
  (map-get? clinic-performance-history { clinic-id: clinic-id, period: period })
)

(define-read-only (get-oracle-address)
  (var-get oracle-address)
)

(define-read-only (has-voted (clinic-id uint) (voter principal))
  (is-some (map-get? clinic-votes { clinic-id: clinic-id, voter: voter }))
)

(define-read-only (get-next-clinic-id)
  (var-get next-clinic-id)
)

(define-read-only (calculate-disbursement (clinic-id uint))
  (let
    (
      (clinic-data (map-get? clinics { clinic-id: clinic-id }))
      (pool-balance (var-get total-pool-balance))
    )
    (match clinic-data
      clinic
      (let
        (
          (performance-score (get performance-score clinic))
        )
        (if (>= performance-score MIN_PERFORMANCE_SCORE)
          (some (/ (* pool-balance performance-score) u10000))
          none
        )
      )
      none
    )
  )
)

(define-read-only (get-donor-tier (donor principal))
  (map-get? donor-loyalty-tiers { donor: donor })
)

(define-read-only (get-milestone-reward-status (donor principal) (milestone uint))
  (map-get? milestone-rewards { donor: donor, milestone: milestone })
)

(define-read-only (calculate-available-milestone-rewards (donor principal))
  (let
    (
      (donor-stats (map-get? donor-contributions { donor: donor }))
    )
    (match donor-stats
      stats
      (let
        (
          (total-donated (get total-donated stats))
        )
        {
          milestone-1: (calculate-milestone-reward u1 total-donated),
          milestone-2: (calculate-milestone-reward u2 total-donated),
          milestone-3: (calculate-milestone-reward u3 total-donated),
          milestone-4: (calculate-milestone-reward u4 total-donated)
        }
      )
      {
        milestone-1: u0,
        milestone-2: u0,
        milestone-3: u0,
        milestone-4: u0
      }
    )
  )
)

(define-read-only (get-donor-voting-power (donor principal))
  (get-voting-power donor)
)

(define-read-only (get-audit-event (event-id uint))
  (map-get? audit-events { event-id: event-id })
)

(define-read-only (get-clinic-audit-summary (clinic-id uint))
  (map-get? clinic-audit-counters { clinic-id: clinic-id })
)

(define-read-only (get-recent-audit-event-for-clinic (clinic-id uint))
  (let
    (
      (audit-summary (map-get? clinic-audit-counters { clinic-id: clinic-id }))
    )
    (match audit-summary
      summary
      (map-get? audit-events { event-id: (get last-event-id summary) })
      none
    )
  )
)

(define-read-only (get-total-audit-events)
  (- (var-get next-audit-event-id) u1)
)

(define-read-only (verify-clinic-integrity (clinic-id uint))
  (let
    (
      (clinic-data (map-get? clinics { clinic-id: clinic-id }))
      (audit-summary (map-get? clinic-audit-counters { clinic-id: clinic-id }))
    )
    (match clinic-data
      clinic
      (match audit-summary
        summary
        {
          clinic-exists: true,
          total-events: (get event-count summary),
          registration-verified: (> (get event-count summary) u0),
          current-status: (get status clinic),
          last-audit-event: (get last-event-id summary)
        }
        {
          clinic-exists: true,
          total-events: u0,
          registration-verified: false,
          current-status: (get status clinic),
          last-audit-event: u0
        }
      )
      {
        clinic-exists: false,
        total-events: u0,
        registration-verified: false,
        current-status: "not-found",
        last-audit-event: u0
      }
    )
  )
)

(define-read-only (get-subscription-details (subscriber principal))
  (map-get? recurring-subscriptions { subscriber: subscriber })
)

(define-read-only (is-subscription-due (subscriber principal))
  (let
    (
      (subscription (map-get? recurring-subscriptions { subscriber: subscriber }))
    )
    (match subscription
      sub
      (if (get is-active sub)
        (some (>= stacks-block-height (get next-payment-block sub)))
        (some false)
      )
      none
    )
  )
)

(define-read-only (get-subscription-stats (subscriber principal))
  (let
    (
      (subscription (map-get? recurring-subscriptions { subscriber: subscriber }))
    )
    (match subscription
      sub
      (some {
        total-contributed: (* (get amount sub) (get total-payments sub)),
        payments-made: (get total-payments sub),
        next-due-block: (get next-payment-block sub),
        is-active: (get is-active sub)
      })
      none
    )
  )
)
