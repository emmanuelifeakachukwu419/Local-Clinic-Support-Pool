;; Appointment Scheduling System Smart Contract
;; Local Clinic Support Pool - Manage patient appointments and clinic availability

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-APPOINTMENT-NOT-FOUND (err u301))
(define-constant ERR-INVALID-TIME-SLOT (err u302))
(define-constant ERR-SLOT-ALREADY-BOOKED (err u303))
(define-constant ERR-INVALID-CLINIC-ID (err u304))
(define-constant ERR-PAST-DATE (err u305))
(define-constant ERR-APPOINTMENT-CONFIRMED (err u306))
(define-constant ERR-INVALID-STATUS (err u307))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Appointment statuses
(define-constant STATUS-PENDING u1)
(define-constant STATUS-CONFIRMED u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-CANCELLED u4)

;; Time slots (hours in 24-hour format)
(define-constant SLOT-09-00 u900)
(define-constant SLOT-10-00 u1000)
(define-constant SLOT-11-00 u1100)
(define-constant SLOT-14-00 u1400)
(define-constant SLOT-15-00 u1500)
(define-constant SLOT-16-00 u1600)

;; Data structures
(define-map appointments
  { appointment-id: uint }
  {
    patient: principal,
    clinic-id: uint,
    appointment-date: uint,
    time-slot: uint,
    appointment-type: (string-ascii 30),
    status: uint,
    doctor: (string-ascii 40),
    notes: (string-ascii 200),
    created-at: uint,
    updated-at: uint
  })

(define-map clinic-schedules
  { clinic-id: uint, date: uint, time-slot: uint }
  {
    is-available: bool,
    appointment-id: (optional uint),
    max-appointments: uint,
    current-bookings: uint
  })

(define-map clinic-availability
  uint
  {
    name: (string-ascii 50),
    operating-hours: (list 6 uint),
    max-daily-appointments: uint,
    advance-booking-days: uint,
    is-active: bool
  })

;; Data variables
(define-data-var next-appointment-id uint u1)
(define-data-var total-appointments uint u0)

;; Read-only functions
(define-read-only (get-appointment (appointment-id uint))
  (map-get? appointments { appointment-id: appointment-id }))

(define-read-only (get-clinic-availability (clinic-id uint))
  (map-get? clinic-availability clinic-id))

(define-read-only (get-schedule-slot (clinic-id uint) (date uint) (time-slot uint))
  (map-get? clinic-schedules { clinic-id: clinic-id, date: date, time-slot: time-slot }))

(define-read-only (is-valid-time-slot (time-slot uint))
  (or (is-eq time-slot SLOT-09-00)
      (or (is-eq time-slot SLOT-10-00)
          (or (is-eq time-slot SLOT-11-00)
              (or (is-eq time-slot SLOT-14-00)
                  (or (is-eq time-slot SLOT-15-00)
                      (is-eq time-slot SLOT-16-00)))))))

(define-read-only (check-slot-availability (clinic-id uint) (date uint) (time-slot uint))
  (match (map-get? clinic-schedules { clinic-id: clinic-id, date: date, time-slot: time-slot })
    slot-data
      (ok {
        is-available: (get is-available slot-data),
        current-bookings: (get current-bookings slot-data),
        max-appointments: (get max-appointments slot-data)
      })
    (ok { is-available: true, current-bookings: u0, max-appointments: u1 })))

(define-read-only (get-system-stats)
  (ok {
    total-appointments: (var-get total-appointments),
    next-appointment-id: (var-get next-appointment-id)
  }))

;; Public functions

;; Register clinic with availability settings
(define-public (register-clinic-schedule 
  (clinic-id uint)
  (name (string-ascii 50))
  (operating-hours (list 6 uint))
  (max-daily-appointments uint)
  (advance-booking-days uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> max-daily-appointments u0) ERR-INVALID-TIME-SLOT)
    
    (map-set clinic-availability clinic-id {
      name: name,
      operating-hours: operating-hours,
      max-daily-appointments: max-daily-appointments,
      advance-booking-days: advance-booking-days,
      is-active: true
    })
    
    (ok clinic-id)))

;; Book an appointment
(define-public (book-appointment 
  (clinic-id uint)
  (appointment-date uint)
  (time-slot uint)
  (appointment-type (string-ascii 30))
  (doctor (string-ascii 40))
  (notes (string-ascii 200)))
  (let ((appointment-id (var-get next-appointment-id))
        (clinic-info (unwrap! (map-get? clinic-availability clinic-id) ERR-INVALID-CLINIC-ID)))
    
    ;; Validate inputs
    (asserts! (is-valid-time-slot time-slot) ERR-INVALID-TIME-SLOT)
    (asserts! (> appointment-date block-height) ERR-PAST-DATE)
    (asserts! (get is-active clinic-info) ERR-INVALID-CLINIC-ID)
    
    ;; Check slot availability
    (let ((slot-info (unwrap-panic (check-slot-availability clinic-id appointment-date time-slot))))
      (asserts! (get is-available slot-info) ERR-SLOT-ALREADY-BOOKED)
      
      ;; Create appointment
      (map-set appointments 
        { appointment-id: appointment-id }
        {
          patient: tx-sender,
          clinic-id: clinic-id,
          appointment-date: appointment-date,
          time-slot: time-slot,
          appointment-type: appointment-type,
          status: STATUS-PENDING,
          doctor: doctor,
          notes: notes,
          created-at: block-height,
          updated-at: block-height
        })
      
      ;; Update schedule slot
      (map-set clinic-schedules
        { clinic-id: clinic-id, date: appointment-date, time-slot: time-slot }
        {
          is-available: false,
          appointment-id: (some appointment-id),
          max-appointments: u1,
          current-bookings: u1
        })
      
      ;; Update counters
      (var-set next-appointment-id (+ appointment-id u1))
      (var-set total-appointments (+ (var-get total-appointments) u1))
      
      (ok appointment-id))))

;; Confirm appointment
(define-public (confirm-appointment (appointment-id uint))
  (let ((appointment-info (unwrap! (map-get? appointments { appointment-id: appointment-id }) ERR-APPOINTMENT-NOT-FOUND)))
    (asserts! (is-eq (get status appointment-info) STATUS-PENDING) ERR-APPOINTMENT-CONFIRMED)
    
    ;; Update appointment status
    (map-set appointments 
      { appointment-id: appointment-id }
      (merge appointment-info {
        status: STATUS-CONFIRMED,
        updated-at: block-height
      }))
    
    (ok true)))

;; Cancel appointment
(define-public (cancel-appointment (appointment-id uint))
  (let ((appointment-info (unwrap! (map-get? appointments { appointment-id: appointment-id }) ERR-APPOINTMENT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get patient appointment-info)) ERR-UNAUTHORIZED)
    (asserts! (< (get status appointment-info) STATUS-COMPLETED) ERR-INVALID-STATUS)
    
    ;; Update appointment status
    (map-set appointments 
      { appointment-id: appointment-id }
      (merge appointment-info {
        status: STATUS-CANCELLED,
        updated-at: block-height
      }))
    
    ;; Free up the time slot
    (map-set clinic-schedules
      { clinic-id: (get clinic-id appointment-info), 
        date: (get appointment-date appointment-info), 
        time-slot: (get time-slot appointment-info) }
      {
        is-available: true,
        appointment-id: none,
        max-appointments: u1,
        current-bookings: u0
      })
    
    (ok true)))

;; Initialize sample clinic
(map-set clinic-availability u1 {
  name: "General Health Clinic",
  operating-hours: (list SLOT-09-00 SLOT-10-00 SLOT-11-00 SLOT-14-00 SLOT-15-00 SLOT-16-00),
  max-daily-appointments: u20,
  advance-booking-days: u30,
  is-active: true
})

;; Initialize system variables
(var-set next-appointment-id u1)
(var-set total-appointments u0)
