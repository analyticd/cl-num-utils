;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8 -*-

(in-package #:cl-num-utils)

;;; WITH-RANGE-INDEXING is the user interface of an iteration
;;; construct that walks the (indexes of the) elements on an array.
;;; Indexing can be row- or column-major, or even represent axis
;;; permutations, etc, but order of traversal is contiguous only for
;;; row-major arrays.
;;;
;;; Here is how it works:
;;;
;;; 0. Conventions: TRANSFORM-RANGES is the only function which
;;;    accepts all kinds of sequences.  Everything else operates on
;;;    VECTORs, SIMPLE-FIXNUM-VECTORs when applicable (everything is a
;;;    FIXNUM except ranges).
;;;
;;; 1. A *range speficiation* is required for each axis.  The
;;;    following options are possible:
;;;
;;;    a. T, selecting all indices along that dimension
;;;
;;;    b. a single fixnum, which selects an index along that
;;;       dimension, and the dimensions is dropped
;;;
;;;    c. (cons start end), both fixnums, with start < end (the latter
;;;       exclusive, as is conventional for CL, see subseq, etc)
;;;
;;;    d. a vector of fixnums, selecting arbitrary indexes
;;;
;;;    Zero has a special interpretation as END: it denoted the
;;;    dimension along that axis.
;;;
;;;    Negative numbers count backwards from the dimension: eg -1
;;;    denotes dimension-1.
;;;
;;; 2. An affine mapping is established, which is the sum of indexes
;;;    multiplied by corresponding coefficients.  This is general
;;;    enough to permit row- and colum-major mappings, or even axis
;;;    permutations.
;;;
;;; 3. Dropped dimensions (denoted by a single integer) are removed,
;;;    and the corresponding partial sum is added as an offset.
;;;
;;; 4. An index counter (a vector of fixnums) is initialized with
;;;    zeros, and incremented with each step.  The set of indices
;;;    changed is kept track of.  The sum of coefficients is
;;;    calculated, using partial sums from previous iterations to the
;;;    extent it is possible.

(define-condition sub-incompatible-dimensions (error)
  ()
  (:documentation "Either rank or dimensions are incompatible."))

(deftype simple-fixnum-vector ()
  '(simple-array fixnum (*)))

(define-condition sub-invalid-array-index (error)
  ((index :accessor index :initarg :index)
   (dimension :accessor dimension :initarg :dimension)))

(define-condition sub-invalid-range (error)
  ((range :accessor range :initarg :range)))

(defun transform-index (index dimension end?)
  "Transform an index and check its validity within a given dimension.
Positive numbers mapped to themselves, negative numbers result in
dimension+index.  If end?, 0 yields dimension, otherwise 0."
  (cond
    ((zerop index)
     (if end?
         dimension
         0))
    ((minusp index) (aprog1 (+ dimension index)
                      (assert (<= 0 it) () 'sub-invalid-array-index
                              :index index :dimension dimension)))
    (t (assert (if end?
                   (<= index dimension)
                   (< index dimension))
               () 'sub-invalid-array-index
               :index index :dimension dimension)
     index)))

(deftype sub-all ()
  '(and boolean (not null)))

(deftype sub-index ()
  'fixnum)

(deftype sub-range ()
  '(cons fixnum fixnum))


(defun transform-range (range dimension)
  "Transform indexes in a range.  Checks that contiguous ranges are
valid."
  (etypecase range
    (sub-all (cons 0 dimension))
    (sub-index (transform-index range dimension nil))
    (sub-range (bind ((start (transform-index (car range) dimension
                                              nil))
                      (end (transform-index (cdr range) dimension t)))
                 (assert (< start end) () 'sub-invalid-range
                         :range range)
                 (cons start end)))
    (vector (map 'simple-fixnum-vector
                 (lambda (index) (transform-index index dimension nil))
                 range))))

(defun transform-ranges (ranges dimensions)
  "Transform multiple ranges."
  (map 'vector #'transform-range ranges dimensions))

(defun row-major-coefficients (dimensions)
  "Calculate coefficients for row-major mapping."
  (let* ((cumprod 1)
         (rank (length dimensions))
         (coefficients (make-array rank :element-type 'fixnum)))
    (iter
      (for axis-number :from (1- rank) :downto 0)
      (setf (aref coefficients axis-number) cumprod
            cumprod (* cumprod (aref dimensions axis-number))))
    coefficients))

(defun column-major-coefficients (dimensions)
  "Calculate coefficients for a column-major mapping."
  (let* ((cumprod 1)
         (rank (length dimensions))
         (coefficients (make-array rank :element-type 'fixnum)))
    (iter
      (for axis-number :from 0 :below rank)
      (setf (aref coefficients axis-number) cumprod
            cumprod (* cumprod (aref dimensions axis-number))))
    coefficients))

(defun drop-dimensions (ranges coefficients)
  "Drop single dimensions.  Return (values OFFSET NEW-RANGES
NEW-COEFFICIENTS)."
  (iter
    (with offset := 0)
    (for range :in-vector ranges)
    (for coefficient :in-vector coefficients)
    (if (numberp range)
        (incf offset (* range coefficient))
        (progn
          (collect range :into new-ranges :result-type vector)
          (collect coefficient :into new-coefficients
                   :result-type simple-fixnum-vector)))
    (finally
     (return (values offset
                     new-ranges
                     new-coefficients)))))

(defun range-dimension (range)
  "Dimension of a range."
  (etypecase range
    (number 1)
    (cons (- (cdr range) (car range)))
    (vector (length range))))

(defun range-dimensions (ranges)
  "Dimensions of ranges."
  (map 'simple-fixnum-vector #'range-dimension ranges))

(defun map-counter (range counter)
  "Map an index (starting from zero) to an index within a range.  No
validity checks, this function is meant for internal use and always
expects a valid index."
  (etypecase range
    (number range)
    (cons (+ (car range) counter))
    (vector (aref range counter))))

(defun increment-index-counters (counters range-dimensions)
  "Increment index counters, beginning from the end.  Return the index
of the last one that was changed.  The second value is T when the
first index has reached its limit, ie the array has been walked and
all the counters are zero again."
  (iter
    (for axis-number :from (1- (length range-dimensions)) :downto 0)
    (if (= (incf (aref counters axis-number))
           (aref range-dimensions axis-number))
        (setf (aref counters axis-number) 0)
        (return-from increment-index-counters axis-number)))
  (values 0 t))


(defun map-counters (offset ranges coefficients counters cumsums
                     valid-end)
  "Recalculate cumsums, return flat index."
  (let ((cumsum (if (zerop valid-end)
                    offset
                    (aref cumsums (1- valid-end)))))
    (iter
      (for counter :in-vector counters :from valid-end
           :with-index axis-number)
      (for range :in-vector ranges :from valid-end)
      (for coefficient :in-vector coefficients :from valid-end)
      (incf cumsum (* coefficient (map-counter range counter)))
      (setf (aref cumsums axis-number) cumsum))
    cumsum))

(defmacro with-range-indexing ((ranges dimensions next-index
                                       &key
                                       (end? (gensym "END"))
                                       (range-dimensions 
                                        (gensym "RANGE-DIMENSIONS"))
                                       (counters
                                        (gensym "COUNTERS")))
                               &body body)
  "Establish incrementation and index-calculation functions within
body.  The sequence RANGES is a range specification."
  (check-type next-index symbol)
  (check-type end? symbol)
  (once-only (dimensions ranges)
    (with-unique-names (coefficients offset rank cumsums valid-end)
      `(bind ((,dimensions (coerce ,dimensions 'simple-fixnum-vector))
              (,ranges (transform-ranges ,ranges ,dimensions)))
         (assert (= (length ,ranges) (length ,dimensions)) ()
                 "Length of range specifiation does not match rank.")
         (bind ((,coefficients (row-major-coefficients ,dimensions))
                ((:values ,offset ,ranges ,coefficients)
                 (drop-dimensions ,ranges ,coefficients))
                (,rank (length ,ranges))
                (,range-dimensions (range-dimensions ,ranges))
                (,counters (make-array ,rank :element-type 'fixnum))
                (,cumsums (make-array ,rank :element-type 'fixnum))
                (,valid-end 0)
                (,end? (every #'zerop ,range-dimensions))
                ((:flet ,next-index ())
                 (aprog1 (map-counters ,offset ,ranges ,coefficients
                                       ,counters ,cumsums 
                                       ,valid-end)
                   (setf (values ,valid-end ,end?)
                         (increment-index-counters 
                          ,counters
                          ,range-dimensions)))))
           ;; !!! dynamic extent & type declarations, check
           ;; !!! optimizations
           ,@body)))))

(defgeneric sub (object &rest ranges)
  (:documentation ""))

(defmethod sub ((array array) &rest ranges)
  (with-range-indexing (ranges (array-dimensions array) next-index
                               :end? end?
                               :range-dimensions dimensions)
    (if (zerop (length dimensions))
        (row-major-aref array (next-index))
        (let ((result (make-array (coerce dimensions 'list)
                                  :element-type
                                  (array-element-type array))))
          (iter
            (until end?)
            (for result-index :from 0)
            (setf (row-major-aref result result-index)
                  (row-major-aref array (next-index))))
          result))))

(defmethod sub ((list list) &rest ranges)
  (assert (= 1 (length ranges)))
  (with-range-indexing (ranges (list (length list)) next-index
                               :end? end?
                               :range-dimensions dimensions)
    ;; !!! very inefficient method, could do much better
    (iter
      (until end?)
      (collecting (nth (next-index) list)))))

(defgeneric (setf sub) (source target &rest ranges)
  (:documentation ""))

(defmethod (setf sub) ((source array) (target array) &rest ranges)
  (with-range-indexing (ranges (array-dimensions target) next-index
                               :end? end? 
                               :range-dimensions dimensions)
    (assert (equalp dimensions 
                    (coerce (array-dimensions source) 'vector))
            () 'sub-incompatible-dimensions)
    (iter
      (until end?)
      (for source-index :from 0)
      (setf (row-major-aref target (next-index))
            (row-major-aref source source-index))))
  source)

;;; !!! write (setf sub) for list

(defgeneric map-columns (matrix function)
  (:documentation "Map columns of MATRIX using function.  FUNCTION is
  called with columns that are extracted as a vector, and the returned
  values are assembled into another matrix.  Element types and number
  of rows are established after the first function call, and are
  checked for conformity after that.  If function doesn't return a
  vector, the values are collected in a vector instead of a matrix."))

(defmethod map-columns ((matrix array) function)
  (bind (((nil ncol) (array-dimensions matrix))
         result
         result-nrow)
    (iter
      (for col :from 0 :below ncol)
      (let ((mapped-col (funcall function (sub matrix t col))))
        (when (first-iteration-p)
          (if (vectorp mapped-col)
              (setf result-nrow (length mapped-col)
                    result (make-array (list result-nrow ncol)
                                       :element-type
                                       (array-element-type mapped-col)))
              (setf result (make-array ncol))))
        (if result-nrow
            (setf (sub result t col) mapped-col)
            (setf (aref result col) mapped-col))))
    result))

(defgeneric map-rows (matrix function)
  (:documentation "Similar to MAP-ROWS, mutatis mutandis."))

(defmethod map-rows ((matrix array) function)
  (bind (((nrow nil) (array-dimensions matrix))
         result
         result-ncol)
    (iter
      (for row :from 0 :below nrow)
      (let ((mapped-row (funcall function (sub matrix row t))))
        (when (first-iteration-p)
          (if (vectorp mapped-row)
              (setf result-ncol (length mapped-row)
                    result (make-array (list nrow result-ncol)
                                       :element-type
                                       (array-element-type mapped-row)))
              (setf result (make-array nrow))))
        (if result-ncol
            (setf (sub result row t) mapped-row)
            (setf (aref result row) mapped-row))))
    result))

(defgeneric transpose (object)
  (:documentation "Transpose a matrix.")) 

(defmethod transpose ((matrix array))
  ;; transpose a matrix
  (bind (((nrow ncol) (array-dimensions matrix))
         (result (make-array (list ncol nrow) :element-type (array-element-type matrix)))
         (result-index 0))
    (dotimes (col ncol)
      (dotimes (row nrow)
        (setf (row-major-aref result result-index) (aref matrix row col))
        (incf result-index)))
    result))

(defgeneric create (type element-type &rest dimensions)
  (:documentation "Create an object of TYPE with given DIMENSIONS and
  ELEMENT-TYPE (or a supertype thereof)."))

(defmethod create ((type (eql 'array)) element-type &rest dimensions)
  (make-array dimensions :element-type element-type))

(defmethod collect-rows (nrow function &optional (type 'array))
  (bind (result
         ncol)
    (iter
      (for row :from 0 :below nrow)
      (let ((result-row (funcall function)))
        (when (first-iteration-p)
          (setf ncol (length result-row)
                result (create type (array-element-type result-row) nrow ncol)))
        (setf (sub result row t) result-row)))
    result))

(defun collect-vector (n function &optional (element-type t))
  (bind (result)
    (iter
      (for index :from 0 :below n)
      (let ((element (funcall function)))
        (when (first-iteration-p)
          (setf result (make-array n :element-type element-type)))
        (setf (aref result index) element)))
    result))


