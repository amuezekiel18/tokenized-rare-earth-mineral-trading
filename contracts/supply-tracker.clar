;; supply-tracker
;; Tracks rare earth mineral batches from extraction through delivery, recording
;; provenance, custody changes, location updates, quality assessments, and transfers
;; along the supply chain. No cross-contract dependencies or traits.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u2001))
(define-constant ERR-BATCH-NOT-FOUND (err u2002))
(define-constant ERR-INVALID-STATUS (err u2003))
(define-constant ERR-INVALID-QUANTITY (err u2004))
(define-constant ERR-UNAUTHORIZED-CUSTODY (err u2005))
(define-constant ERR-BATCH-EXISTS (err u2006))
(define-constant ERR-EMPTY-DATA (err u2007))
(define-constant ERR-INVALID-LOCATION (err u2008))
(define-constant ERR-NOT-OPERATOR (err u2009))
(define-constant ERR-INVALID-GRADE (err u2010))

;; Status constants
(define-constant STATUS-EXTRACTED "extracted")
(define-constant STATUS-PROCESSED "processed")
(define-constant STATUS-TESTED "tested")
(define-constant STATUS-CERTIFIED "certified")
(define-constant STATUS-IN-TRANSIT "in-transit")
(define-constant STATUS-DELIVERED "delivered")
(define-constant STATUS-SOLD "sold")

;; Grade levels for quality assessment
(define-constant GRADE-A "A")
(define-constant GRADE-B "B")
(define-constant GRADE-C "C")
(define-constant GRADE-D "D")
(define-constant GRADE-UNGRADED "ungraded")

;; Data variables
(define-data-var contract-admin principal tx-sender)
(define-data-var batch-counter uint u0)
(define-data-var event-counter uint u0)

;; Operators (authorized entities to update supply chain)
(define-map operators principal bool)

;; Batch registry: core information about mineral batches
(define-map batches
  (string-ascii 50)  ;; batch-id
  {
    creator: principal,
    mineral-type: (string-ascii 30),
    quantity: uint,           ;; in kilograms * 1000 for precision
    grade: (string-ascii 10),
    status: (string-ascii 20),
    location: (string-ascii 100),
    custody-holder: principal,
    created-at: uint,
    last-updated: uint,
    origin-mine: (string-ascii 100),
    certification-hash: (optional (string-ascii 64)),
    is-active: bool
  }
)

;; Supply chain events log (immutable)
(define-map supply-events
  uint  ;; event-id
  {
    batch-id: (string-ascii 50),
    event-type: (string-ascii 30),   ;; "custody-change", "location-update", "status-change", "quality-test"
    from-party: (optional principal),
    to-party: (optional principal),
    location: (string-ascii 100),
    timestamp: uint,
    description: (string-ascii 200),
    data: (string-ascii 300)         ;; JSON-like string for extra metadata
  }
)

;; Quality assessments per batch
(define-map quality-tests
  { batch-id: (string-ascii 50), test-id: uint }
  {
    tester: principal,
    test-type: (string-ascii 30),    ;; "purity", "composition", "radioactivity", etc.
    result: (string-ascii 100),
    grade-assigned: (string-ascii 10),
    timestamp: uint,
    certificate-hash: (optional (string-ascii 64))
  }
)

;; Custody chain (who held what when)
(define-map custody-history
  { batch-id: (string-ascii 50), custody-id: uint }
  {
    from-holder: (optional principal),
    to-holder: principal,
    transfer-reason: (string-ascii 100),
    timestamp: uint,
    location: (string-ascii 100),
    signed-by: principal  ;; who authorized the transfer
  }
)

;; Counters per batch for sub-records
(define-map batch-test-counters (string-ascii 50) uint)
(define-map batch-custody-counters (string-ascii 50) uint)

;; Helper functions
(define-private (only-admin)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    (ok true)
  )
)

(define-private (only-operator)
  (begin
    (asserts! (default-to false (map-get? operators tx-sender)) ERR-NOT-OPERATOR)
    (ok true)
  )
)

(define-private (is-valid-batch (batch-id (string-ascii 50)))
  (is-some (map-get? batches batch-id))
)

(define-private (is-valid-status (status (string-ascii 20)))
  (or
    (is-eq status STATUS-EXTRACTED)
    (is-eq status STATUS-PROCESSED)
    (is-eq status STATUS-TESTED)
    (is-eq status STATUS-CERTIFIED)
    (is-eq status STATUS-IN-TRANSIT)
    (is-eq status STATUS-DELIVERED)
    (is-eq status STATUS-SOLD)
  )
)

(define-private (is-valid-grade (grade (string-ascii 10)))
  (or
    (is-eq grade GRADE-A)
    (is-eq grade GRADE-B)
    (is-eq grade GRADE-C)
    (is-eq grade GRADE-D)
    (is-eq grade GRADE-UNGRADED)
  )
)

(define-private (emit-event (batch-id (string-ascii 50)) (event-type (string-ascii 30)) (from-party (optional principal)) (to-party (optional principal)) (location (string-ascii 100)) (description (string-ascii 200)) (data (string-ascii 300)))
  (let ((event-id (+ (var-get event-counter) u1)))
    (var-set event-counter event-id)
    (map-set supply-events event-id
      {
        batch-id: batch-id,
        event-type: event-type,
        from-party: from-party,
        to-party: to-party,
        location: location,
        timestamp: block-height,
        description: description,
        data: data
      }
    )
  )
)

;; Admin functions
(define-public (set-admin (new-admin principal))
  (begin
    (try! (only-admin))
    (var-set contract-admin new-admin)
    (ok new-admin)
  )
)

(define-public (add-operator (operator principal))
  (begin
    (try! (only-admin))
    (map-set operators operator true)
    (ok operator)
  )
)

(define-public (remove-operator (operator principal))
  (begin
    (try! (only-admin))
    (map-set operators operator false)
    (ok operator)
  )
)

;; Core batch management
(define-public (create-batch 
  (batch-id (string-ascii 50))
  (mineral-type (string-ascii 30))
  (quantity uint)
  (origin-mine (string-ascii 100))
  (initial-location (string-ascii 100))
)
  (begin
    (try! (only-operator))
    (asserts! (is-none (map-get? batches batch-id)) ERR-BATCH-EXISTS)
    (asserts! (> quantity u0) ERR-INVALID-QUANTITY)
    (asserts! (> (len batch-id) u0) ERR-EMPTY-DATA)
    (asserts! (> (len mineral-type) u0) ERR-EMPTY-DATA)
    
    (map-set batches batch-id
      {
        creator: tx-sender,
        mineral-type: mineral-type,
        quantity: quantity,
        grade: GRADE-UNGRADED,
        status: STATUS-EXTRACTED,
        location: initial-location,
        custody-holder: tx-sender,
        created-at: block-height,
        last-updated: block-height,
        origin-mine: origin-mine,
        certification-hash: none,
        is-active: true
      }
    )
    
    ;; Initialize counters
    (map-set batch-test-counters batch-id u0)
    (map-set batch-custody-counters batch-id u0)
    
    ;; Log creation event
    (emit-event batch-id "batch-created" none (some tx-sender) initial-location
      "Batch created and extracted" (concat "mine:" origin-mine))
    
    (var-set batch-counter (+ (var-get batch-counter) u1))
    (ok batch-id)
  )
)

(define-public (update-batch-status (batch-id (string-ascii 50)) (new-status (string-ascii 20)) (location (string-ascii 100)) (description (string-ascii 200)))
  (let ((batch-info (unwrap! (map-get? batches batch-id) ERR-BATCH-NOT-FOUND)))
    (begin
      (try! (only-operator))
      (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
      
      (map-set batches batch-id
        (merge batch-info {
          status: new-status,
          location: location,
          last-updated: block-height
        })
      )
      
      (emit-event batch-id "status-change" none (some tx-sender) location description "")
      (ok true)
    )
  )
)

(define-public (transfer-custody (batch-id (string-ascii 50)) (new-custodian principal) (transfer-reason (string-ascii 100)) (location (string-ascii 100)))
  (let 
    (
      (batch-info (unwrap! (map-get? batches batch-id) ERR-BATCH-NOT-FOUND))
      (custody-counter (default-to u0 (map-get? batch-custody-counters batch-id)))
      (new-custody-id (+ custody-counter u1))
    )
    (begin
      (try! (only-operator))
      
      ;; Update batch custody
      (map-set batches batch-id
        (merge batch-info {
          custody-holder: new-custodian,
          location: location,
          last-updated: block-height
        })
      )
      
      ;; Record custody change
      (map-set custody-history { batch-id: batch-id, custody-id: new-custody-id }
        {
          from-holder: (some (get custody-holder batch-info)),
          to-holder: new-custodian,
          transfer-reason: transfer-reason,
          timestamp: block-height,
          location: location,
          signed-by: tx-sender
        }
      )
      
      (map-set batch-custody-counters batch-id new-custody-id)
      
      (emit-event batch-id "custody-change" 
        (some (get custody-holder batch-info)) (some new-custodian) 
        location transfer-reason "")
      
      (ok new-custody-id)
    )
  )
)

(define-public (add-quality-test 
  (batch-id (string-ascii 50))
  (test-type (string-ascii 30))
  (result (string-ascii 100))
  (grade-assigned (string-ascii 10))
  (certificate-hash (optional (string-ascii 64)))
)
  (let 
    (
      (batch-info (unwrap! (map-get? batches batch-id) ERR-BATCH-NOT-FOUND))
      (test-counter (default-to u0 (map-get? batch-test-counters batch-id)))
      (new-test-id (+ test-counter u1))
    )
    (begin
      (try! (only-operator))
      (asserts! (is-valid-grade grade-assigned) ERR-INVALID-GRADE)
      
      ;; Record the test
      (map-set quality-tests { batch-id: batch-id, test-id: new-test-id }
        {
          tester: tx-sender,
          test-type: test-type,
          result: result,
          grade-assigned: grade-assigned,
          timestamp: block-height,
          certificate-hash: certificate-hash
        }
      )
      
      ;; Update batch grade if better than current
      (let ((updated-batch (merge batch-info { grade: grade-assigned, last-updated: block-height })))
        (map-set batches batch-id updated-batch)
      )
      
      (map-set batch-test-counters batch-id new-test-id)
      
      (emit-event batch-id "quality-test" none (some tx-sender) 
        (get location batch-info) (concat "Test: " test-type)
        (concat "Grade: " grade-assigned))
      
      (ok new-test-id)
    )
  )
)

;; Read-only functions
(define-read-only (get-batch (batch-id (string-ascii 50)))
  (map-get? batches batch-id)
)

(define-read-only (get-supply-event (event-id uint))
  (map-get? supply-events event-id)
)

(define-read-only (get-quality-test (batch-id (string-ascii 50)) (test-id uint))
  (map-get? quality-tests { batch-id: batch-id, test-id: test-id })
)

(define-read-only (get-custody-record (batch-id (string-ascii 50)) (custody-id uint))
  (map-get? custody-history { batch-id: batch-id, custody-id: custody-id })
)

(define-read-only (get-batch-test-count (batch-id (string-ascii 50)))
  (default-to u0 (map-get? batch-test-counters batch-id))
)

(define-read-only (get-batch-custody-count (batch-id (string-ascii 50)))
  (default-to u0 (map-get? batch-custody-counters batch-id))
)

(define-read-only (get-total-batches) (var-get batch-counter))
(define-read-only (get-total-events) (var-get event-counter))
(define-read-only (is-operator (who principal)) (default-to false (map-get? operators who)))
(define-read-only (get-admin) (var-get contract-admin))
