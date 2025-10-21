;; Medical Supply Inventory Tracker Smart Contract
;; Local Clinic Support Pool - Track medical supply inventory and automate reorder alerts

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-SUPPLY-NOT-FOUND (err u201))
(define-constant ERR-INVALID-QUANTITY (err u202))
(define-constant ERR-INSUFFICIENT-STOCK (err u203))
(define-constant ERR-ALREADY-EXISTS (err u204))
(define-constant ERR-INVALID-CLINIC-ID (err u205))
(define-constant ERR-EXPIRED-SUPPLY (err u206))
(define-constant ERR-INVALID-THRESHOLD (err u207))
(define-constant ERR-BATCH-NOT-FOUND (err u208))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Supply categories
(define-constant CATEGORY-MEDICATION u1)
(define-constant CATEGORY-EQUIPMENT u2)
(define-constant CATEGORY-CONSUMABLE u3)
(define-constant CATEGORY-EMERGENCY u4)

;; Data structures
(define-map medical-supplies
  { clinic-id: uint, supply-id: uint }
  {
    name: (string-ascii 60),
    category: uint,
    current-quantity: uint,
    minimum-threshold: uint,
    maximum-capacity: uint,
    unit-cost: uint,
    supplier: (string-ascii 40),
    last-restocked: uint,
    expiry-date: uint,
    is-critical: bool
  })

(define-map supply-batches
  { clinic-id: uint, supply-id: uint, batch-id: uint }
  {
    quantity: uint,
    received-date: uint,
    expiry-date: uint,
    lot-number: (string-ascii 20),
    cost-per-unit: uint,
    is-consumed: bool
  })

(define-map clinic-inventory-stats
  uint
  {
    total-supplies: uint,
    low-stock-items: uint,
    expired-items: uint,
    total-value: uint,
    last-audit: uint
  })

(define-map supply-transactions
  { clinic-id: uint, transaction-id: uint }
  {
    supply-id: uint,
    transaction-type: (string-ascii 20), ;; "RESTOCK", "CONSUME", "EXPIRE", "TRANSFER"
    quantity: uint,
    timestamp: uint,
    notes: (string-ascii 100),
    processed-by: principal
  })

;; Data variables
(define-data-var next-supply-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var total-supplies-tracked uint u0)
(define-data-var system-alerts-count uint u0)

;; Read-only functions
(define-read-only (get-supply-info (clinic-id uint) (supply-id uint))
  (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id }))

(define-read-only (get-batch-info (clinic-id uint) (supply-id uint) (batch-id uint))
  (map-get? supply-batches { clinic-id: clinic-id, supply-id: supply-id, batch-id: batch-id }))

(define-read-only (get-clinic-inventory-stats (clinic-id uint))
  (map-get? clinic-inventory-stats clinic-id))

(define-read-only (get-transaction (clinic-id uint) (transaction-id uint))
  (map-get? supply-transactions { clinic-id: clinic-id, transaction-id: transaction-id }))

(define-read-only (check-low-stock (clinic-id uint) (supply-id uint))
  (match (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id })
    supply-data 
      (ok {
        is-low-stock: (<= (get current-quantity supply-data) (get minimum-threshold supply-data)),
        current-quantity: (get current-quantity supply-data),
        minimum-threshold: (get minimum-threshold supply-data),
        reorder-amount: (- (get maximum-capacity supply-data) (get current-quantity supply-data))
      })
    ERR-SUPPLY-NOT-FOUND))

(define-read-only (check-expired-supplies (clinic-id uint) (supply-id uint))
  (match (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id })
    supply-data
      (ok {
        is-expired: (< (get expiry-date supply-data) stacks-block-height),
        expiry-date: (get expiry-date supply-data),
        current-block: stacks-block-height,
        days-until-expiry: (if (>= (get expiry-date supply-data) stacks-block-height)
                            (- (get expiry-date supply-data) stacks-block-height)
                            u0)
      })
    ERR-SUPPLY-NOT-FOUND))

(define-read-only (calculate-inventory-value (clinic-id uint) (supply-id uint))
  (match (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id })
    supply-data
      (ok (* (get current-quantity supply-data) (get unit-cost supply-data)))
    ERR-SUPPLY-NOT-FOUND))

(define-read-only (get-system-stats)
  (ok {
    total-supplies-tracked: (var-get total-supplies-tracked),
    system-alerts-count: (var-get system-alerts-count),
    next-supply-id: (var-get next-supply-id),
    next-batch-id: (var-get next-batch-id)
  }))

;; Public functions

;; Add new medical supply to inventory
(define-public (add-medical-supply 
  (clinic-id uint) 
  (name (string-ascii 60)) 
  (category uint) 
  (initial-quantity uint)
  (minimum-threshold uint)
  (maximum-capacity uint)
  (unit-cost uint)
  (supplier (string-ascii 40))
  (expiry-date uint))
  (let ((supply-id (var-get next-supply-id)))
    (asserts! (> initial-quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (> minimum-threshold u0) ERR-INVALID-THRESHOLD)
    (asserts! (> maximum-capacity minimum-threshold) ERR-INVALID-THRESHOLD)
    (asserts! (<= category u4) ERR-INVALID-QUANTITY)
    (asserts! (> expiry-date stacks-block-height) ERR-EXPIRED-SUPPLY)
    
    ;; Check if supply already exists
    (asserts! (is-none (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id })) ERR-ALREADY-EXISTS)
    
    (map-set medical-supplies 
      { clinic-id: clinic-id, supply-id: supply-id }
      {
        name: name,
        category: category,
        current-quantity: initial-quantity,
        minimum-threshold: minimum-threshold,
        maximum-capacity: maximum-capacity,
        unit-cost: unit-cost,
        supplier: supplier,
        last-restocked: stacks-block-height,
        expiry-date: expiry-date,
        is-critical: (is-eq category CATEGORY-EMERGENCY)
      })
    
    ;; Update clinic stats
    (update-clinic-inventory-stats clinic-id)
    
    ;; Update system counters
    (var-set next-supply-id (+ supply-id u1))
    (var-set total-supplies-tracked (+ (var-get total-supplies-tracked) u1))
    
    ;; Record transaction
    (record-supply-transaction clinic-id supply-id "INITIAL_STOCK" initial-quantity "Initial inventory setup")
    
    (ok supply-id)))

;; Restock existing supply
(define-public (restock-supply (clinic-id uint) (supply-id uint) (quantity uint) (new-expiry-date uint) (lot-number (string-ascii 20)))
  (let ((supply-info (unwrap! (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id }) ERR-SUPPLY-NOT-FOUND))
        (batch-id (var-get next-batch-id)))
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (> new-expiry-date stacks-block-height) ERR-EXPIRED-SUPPLY)
    
    ;; Check if restocking would exceed maximum capacity
    (asserts! (<= (+ (get current-quantity supply-info) quantity) (get maximum-capacity supply-info)) ERR-INVALID-QUANTITY)
    
    ;; Create new batch record
    (map-set supply-batches
      { clinic-id: clinic-id, supply-id: supply-id, batch-id: batch-id }
      {
        quantity: quantity,
        received-date: stacks-block-height,
        expiry-date: new-expiry-date,
        lot-number: lot-number,
        cost-per-unit: (get unit-cost supply-info),
        is-consumed: false
      })
    
    ;; Update supply quantity and last restock date
    (map-set medical-supplies 
      { clinic-id: clinic-id, supply-id: supply-id }
      (merge supply-info {
        current-quantity: (+ (get current-quantity supply-info) quantity),
        last-restocked: stacks-block-height,
        expiry-date: (if (> new-expiry-date (get expiry-date supply-info)) new-expiry-date (get expiry-date supply-info))
      }))
    
    ;; Update batch counter
    (var-set next-batch-id (+ batch-id u1))
    
    ;; Update clinic stats
    (update-clinic-inventory-stats clinic-id)
    
    ;; Record transaction
    (record-supply-transaction clinic-id supply-id "RESTOCK" quantity (concat "Restocked with lot: " lot-number))
    
    (ok batch-id)))

;; Consume/use supply items
(define-public (consume-supply (clinic-id uint) (supply-id uint) (quantity uint) (notes (string-ascii 100)))
  (let ((supply-info (unwrap! (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id }) ERR-SUPPLY-NOT-FOUND)))
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (>= (get current-quantity supply-info) quantity) ERR-INSUFFICIENT-STOCK)
    
    ;; Update supply quantity
    (map-set medical-supplies 
      { clinic-id: clinic-id, supply-id: supply-id }
      (merge supply-info { current-quantity: (- (get current-quantity supply-info) quantity) }))
    
    ;; Update clinic stats
    (update-clinic-inventory-stats clinic-id)
    
    ;; Record transaction
    (record-supply-transaction clinic-id supply-id "CONSUME" quantity notes)
    
    ;; Check if now below threshold and increment alerts
    (if (<= (- (get current-quantity supply-info) quantity) (get minimum-threshold supply-info))
      (var-set system-alerts-count (+ (var-get system-alerts-count) u1))
      false)
    
    (ok true)))

;; Mark supplies as expired and remove from active inventory
(define-public (mark-expired (clinic-id uint) (supply-id uint))
  (let ((supply-info (unwrap! (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id }) ERR-SUPPLY-NOT-FOUND)))
    (asserts! (< (get expiry-date supply-info) stacks-block-height) ERR-EXPIRED-SUPPLY)
    
    ;; Record transaction for expired quantity
    (record-supply-transaction clinic-id supply-id "EXPIRE" (get current-quantity supply-info) "Expired supplies removed")
    
    ;; Set quantity to zero
    (map-set medical-supplies 
      { clinic-id: clinic-id, supply-id: supply-id }
      (merge supply-info { current-quantity: u0 }))
    
    ;; Update clinic stats
    (update-clinic-inventory-stats clinic-id)
    (var-set system-alerts-count (+ (var-get system-alerts-count) u1))
    
    (ok true)))

;; Update supply thresholds (admin function)
(define-public (update-thresholds (clinic-id uint) (supply-id uint) (new-minimum uint) (new-maximum uint))
  (let ((supply-info (unwrap! (map-get? medical-supplies { clinic-id: clinic-id, supply-id: supply-id }) ERR-SUPPLY-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> new-minimum u0) ERR-INVALID-THRESHOLD)
    (asserts! (> new-maximum new-minimum) ERR-INVALID-THRESHOLD)
    
    (map-set medical-supplies 
      { clinic-id: clinic-id, supply-id: supply-id }
      (merge supply-info { 
        minimum-threshold: new-minimum, 
        maximum-capacity: new-maximum 
      }))
    
    (ok true)))

;; Get supply alerts for a clinic
(define-read-only (get-clinic-alerts (clinic-id uint))
  (let ((stats (default-to 
    { total-supplies: u0, low-stock-items: u0, expired-items: u0, total-value: u0, last-audit: u0 }
    (map-get? clinic-inventory-stats clinic-id))))
    (ok {
      low-stock-count: (get low-stock-items stats),
      expired-count: (get expired-items stats),
      total-alerts: (+ (get low-stock-items stats) (get expired-items stats)),
      last-audit: (get last-audit stats)
    })))

;; Private helper functions

;; Record supply transaction
(define-private (record-supply-transaction 
  (clinic-id uint) 
  (supply-id uint) 
  (transaction-type (string-ascii 20)) 
  (quantity uint) 
  (notes (string-ascii 100)))
  (let ((transaction-id (var-get next-transaction-id)))
    (map-set supply-transactions
      { clinic-id: clinic-id, transaction-id: transaction-id }
      {
        supply-id: supply-id,
        transaction-type: transaction-type,
        quantity: quantity,
        timestamp: stacks-block-height,
        notes: notes,
        processed-by: tx-sender
      })
    (var-set next-transaction-id (+ transaction-id u1))
    transaction-id))

;; Update clinic inventory statistics
(define-private (update-clinic-inventory-stats (clinic-id uint))
  (let ((current-stats (default-to 
    { total-supplies: u0, low-stock-items: u0, expired-items: u0, total-value: u0, last-audit: u0 }
    (map-get? clinic-inventory-stats clinic-id))))
    
    ;; This is a simplified update - in a full implementation, 
    ;; you'd iterate through all supplies for this clinic
    (map-set clinic-inventory-stats clinic-id
      (merge current-stats { last-audit: stacks-block-height }))
    
    true))

;; Initialize sample medical supplies for clinic 1
(map-set medical-supplies { clinic-id: u1, supply-id: u1 } {
  name: "Surgical Masks",
  category: CATEGORY-CONSUMABLE,
  current-quantity: u500,
  minimum-threshold: u100,
  maximum-capacity: u1000,
  unit-cost: u2,
  supplier: "MedSupply Corp",
  last-restocked: stacks-block-height,
  expiry-date: (+ stacks-block-height u5000),
  is-critical: false
})

(map-set medical-supplies { clinic-id: u1, supply-id: u2 } {
  name: "Emergency Defibrillator",
  category: CATEGORY-EMERGENCY,
  current-quantity: u2,
  minimum-threshold: u1,
  maximum-capacity: u3,
  unit-cost: u50000,
  supplier: "CardioTech Ltd",
  last-restocked: stacks-block-height,
  expiry-date: (+ stacks-block-height u50000),
  is-critical: true
})

;; Initialize system variables
(var-set next-supply-id u3)
(var-set total-supplies-tracked u2)
