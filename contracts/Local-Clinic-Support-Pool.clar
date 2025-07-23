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

(define-constant MIN_DONATION u1000000)
(define-constant MIN_PERFORMANCE_SCORE u70)
(define-constant VOTING_PERIOD u144)
(define-constant DISBURSEMENT_INTERVAL u1008)

(define-data-var total-pool-balance uint u0)
(define-data-var next-clinic-id uint u1)
(define-data-var oracle-address principal CONTRACT_OWNER)

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

(define-public (donate (amount uint))
  (begin
    (asserts! (>= amount MIN_DONATION) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
    (map-set donor-contributions
      { donor: tx-sender }
      {
        total-donated: (+ amount (get total-donated (default-to { total-donated: u0, last-donation-block: u0 } (map-get? donor-contributions { donor: tx-sender })))),
        last-donation-block: stacks-block-height
      }
    )
    (ok amount)
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
    
    (map-set clinic-votes
      { clinic-id: clinic-id, voter: tx-sender }
      { vote: vote, block-height: current-block }
    )
    
    (map-set voting-sessions
      { clinic-id: clinic-id }
      (merge voting-session
        {
          yes-votes: (if vote (+ (get yes-votes voting-session) u1) (get yes-votes voting-session)),
          no-votes: (if vote (get no-votes voting-session) (+ (get no-votes voting-session) u1))
        }
      )
    )
    (ok vote)
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
