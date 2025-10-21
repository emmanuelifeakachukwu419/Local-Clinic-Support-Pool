;; Patient Incentive System Smart Contract
;; Local Clinic Support Pool - Rewards patients for healthcare engagement

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PATIENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-ALREADY-REGISTERED (err u104))
(define-constant ERR-INVALID-CLINIC-ID (err u105))
(define-constant ERR-REWARD-ALREADY-CLAIMED (err u106))
(define-constant ERR-MINIMUM-VISITS-NOT-MET (err u107))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map patients 
  principal 
  {
    total-visits: uint,
    reward-points: uint,
    last-visit: uint,
    clinic-id: uint,
    is-active: bool
  })

(define-map clinics
  uint
  {
    name: (string-ascii 50),
    reward-rate: uint,
    is-verified: bool,
    total-patients: uint
  })

(define-map visit-records
  { patient: principal, visit-id: uint }
  {
    clinic-id: uint,
    visit-type: (string-ascii 30),
    reward-earned: uint,
    timestamp: uint,
    is-completed: bool
  })

;; Data variables
(define-data-var next-clinic-id uint u2) ;; Start at 2 since clinic 1 is pre-initialized
(define-data-var next-visit-id uint u1)
(define-data-var total-rewards-distributed uint u0)
(define-data-var contract-balance uint u1000000) ;; 1M microSTX initial pool

;; Read-only functions
(define-read-only (get-patient-info (patient principal))
  (map-get? patients patient))

(define-read-only (get-clinic-info (clinic-id uint))
  (map-get? clinics clinic-id))

(define-read-only (get-visit-record (patient principal) (visit-id uint))
  (map-get? visit-records { patient: patient, visit-id: visit-id }))

(define-read-only (get-total-rewards-distributed)
  (var-get total-rewards-distributed))

(define-read-only (get-contract-balance)
  (var-get contract-balance))

(define-read-only (calculate-loyalty-bonus (total-visits uint))
  (if (>= total-visits u10)
    u50  ;; 50% bonus for 10+ visits
    (if (>= total-visits u5)
      u25  ;; 25% bonus for 5+ visits
      u0))) ;; No bonus for less than 5 visits

;; Public functions

;; Register new patient
(define-public (register-patient (clinic-id uint))
  (let ((existing-patient (map-get? patients tx-sender))
        (clinic-info (map-get? clinics clinic-id)))
    (asserts! (is-none existing-patient) ERR-ALREADY-REGISTERED)
    (asserts! (is-some clinic-info) ERR-INVALID-CLINIC-ID)
    
    (map-set patients tx-sender {
      total-visits: u0,
      reward-points: u0,
      last-visit: u0,
      clinic-id: clinic-id,
      is-active: true
    })
    
    ;; Update clinic patient count
    (match clinic-info
      clinic-data (map-set clinics clinic-id 
        (merge clinic-data { total-patients: (+ (get total-patients clinic-data) u1) }))
      false)
    
    (ok true)))

;; Register new clinic (only contract owner)
(define-public (register-clinic (name (string-ascii 50)) (reward-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> reward-rate u0) ERR-INVALID-AMOUNT)
    
    (let ((clinic-id (var-get next-clinic-id)))
      (map-set clinics clinic-id {
        name: name,
        reward-rate: reward-rate,
        is-verified: true,
        total-patients: u0
      })
      
      (var-set next-clinic-id (+ clinic-id u1))
      (ok clinic-id))))

;; Record patient visit and award points
(define-public (record-visit (patient principal) (visit-type (string-ascii 30)) (clinic-id uint))
  (let ((patient-info (unwrap! (map-get? patients patient) ERR-PATIENT-NOT-FOUND))
        (clinic-info (unwrap! (map-get? clinics clinic-id) ERR-INVALID-CLINIC-ID))
        (visit-id (var-get next-visit-id)))
    
    ;; Calculate base reward
    (let ((base-reward (get reward-rate clinic-info))
          (loyalty-bonus (calculate-loyalty-bonus (get total-visits patient-info)))
          (total-reward (+ base-reward (/ (* base-reward loyalty-bonus) u100))))
      
      ;; Record the visit
      (map-set visit-records 
        { patient: patient, visit-id: visit-id }
        {
          clinic-id: clinic-id,
          visit-type: visit-type,
          reward-earned: total-reward,
          timestamp: stacks-block-height,
          is-completed: true
        })
      
      ;; Update patient info
      (map-set patients patient 
        (merge patient-info {
          total-visits: (+ (get total-visits patient-info) u1),
          reward-points: (+ (get reward-points patient-info) total-reward),
          last-visit: stacks-block-height
        }))
      
      ;; Update totals
      (var-set next-visit-id (+ visit-id u1))
      (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-reward))
      
      (ok { visit-id: visit-id, reward-earned: total-reward }))))

;; Redeem reward points for STX
(define-public (redeem-points (amount uint))
  (let ((patient-info (unwrap! (map-get? patients tx-sender) ERR-PATIENT-NOT-FOUND)))
    (asserts! (>= (get reward-points patient-info) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (var-get contract-balance) amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Update patient points
    (map-set patients tx-sender 
      (merge patient-info { reward-points: (- (get reward-points patient-info) amount) }))
    
    ;; Update contract balance
    (var-set contract-balance (- (var-get contract-balance) amount))
    
    ;; Transfer STX to patient (simulated - in production would use stx-transfer?)
    (ok amount)))

;; Wellness challenge - bonus points for consistent visits
(define-public (claim-wellness-bonus)
  (let ((patient-info (unwrap! (map-get? patients tx-sender) ERR-PATIENT-NOT-FOUND)))
    (asserts! (>= (get total-visits patient-info) u3) ERR-MINIMUM-VISITS-NOT-MET)
    (asserts! (is-eq (get is-active patient-info) true) ERR-UNAUTHORIZED)
    
    ;; Check if last visit was recent (within 100 blocks)
    (asserts! (>= (get last-visit patient-info) (- stacks-block-height u100)) ERR-REWARD-ALREADY-CLAIMED)
    
    (let ((bonus-points u100)) ;; 100 point wellness bonus
      (map-set patients tx-sender 
        (merge patient-info { reward-points: (+ (get reward-points patient-info) bonus-points) }))
      
      (ok bonus-points))))

;; Admin function to add funds to contract
(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok true)))

;; Emergency pause/unpause patient account
(define-public (toggle-patient-status (patient principal))
  (let ((patient-info (unwrap! (map-get? patients patient) ERR-PATIENT-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (map-set patients patient 
      (merge patient-info { is-active: (not (get is-active patient-info)) }))
    
    (ok (not (get is-active patient-info)))))

;; Get patient statistics
(define-read-only (get-patient-stats (patient principal))
  (match (map-get? patients patient)
    patient-data 
      (ok {
        total-visits: (get total-visits patient-data),
        reward-points: (get reward-points patient-data),
        loyalty-level: (if (>= (get total-visits patient-data) u10) "Gold"
                         (if (>= (get total-visits patient-data) u5) "Silver" "Bronze")),
        next-bonus-visits: (if (< (get total-visits patient-data) u5) (- u5 (get total-visits patient-data))
                             (if (< (get total-visits patient-data) u10) (- u10 (get total-visits patient-data))
                               u0))
      })
    ERR-PATIENT-NOT-FOUND))

;; Initialize with sample clinic
(map-set clinics u1 {
  name: "Community Health Center",
  reward-rate: u50,
  is-verified: true,
  total-patients: u0
})
