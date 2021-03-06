;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8 -*-

(in-package #:cl-num-utils-tests)

(defsuite arithmetic-tests (tests))

(deftest arithmetic-functions (arithmetic-tests)
  (assert-true (same-sign? 1 2 3))
  (assert-false (same-sign? 1 -2 3))
  (assert-eql 4 (square 2))
  (assert-eql 4.0 (absolute-square 2.0))
  (assert-eql 25 (absolute-square #C(3 4)))
  (assert-eql 2 (abs-diff 3 5))
  (assert-eql 2 (abs-diff -3 -5))
  (assert-equality #'num= 2 (log10 100))
  (assert-equality #'num= 8 (log2 256))
  (assert-eql 1/5 (1c 4/5))
  (assert-true (divides? 8 2))
  (assert-false (divides? 8 3))
  (assert-eql 2 (as-integer 2.0))
  (assert-condition error (as-integer 2.5)))

(deftest arithmetic-sequences (arithmetic-tests)
  (assert-equalp #(2 3 4) (numseq 2 4))
  (assert-equalp #(2 4 6 8) (numseq 2 nil :length 4 :by 2))
  (assert-equalp #(0 1 2 3) (ivec 4))
  (assert-equalp #(1 2 3) (ivec 1 4))
  (assert-equalp #(1 3) (ivec 1 4 2))
  (assert-condition error #(1 3) (ivec 4 1 1 t)))

(deftest arithmetic-summaries (arithmetic-tests)
  (let ((v #(2 3 4)))
    (assert-eql 9 (sum v))
    (assert-eql 24 (product v))
    (assert-equalp #(2 5 9) (cumulative-sum v))
    (assert-equalp #(2 6 24) (cumulative-product v))
    (assert-eql 0 (sum #()))
    (assert-eql 1 (product #()))
    (assert-equalp #() (cumulative-sum #()))
    (assert-equalp #() (cumulative-product #()))))

(deftest norms (arithmetic-tests)
  (let* ((a #(2 3 4))
         (a-list (coerce a 'list))
         (b #(#C(3 4) 0 5 5 5))
         (b-list (coerce b 'list)))
    (assert-equality #'num= (sqrt 29) (l2norm a))
    (assert-equality #'num= (sqrt 29) (l2norm a-list))
    (assert-equality #'num= 10 (l2norm b))
    (assert-equality #'num= 10 (l2norm b-list))))

(deftest normalize-probabilities (arithmetic-tests)
  (let* ((a (vector 1 2 7))
         (a-copy (copy-seq a)))
    (assert-equalp #(1/10 2/10 7/10) (normalize-probabilities a))
    (assert-equalp a a-copy)            ; not modified
    (assert-equalp #(0.1d0 0.2d0 0.7d0)
        (normalize-probabilities a :element-type 'double-float))
    (assert-equalp a a-copy)            ; not modified
    (assert-condition error (normalize-probabilities #(1 -1)))
    (let ((normalized #(0.1d0 0.2d0 0.7d0)))
      (assert-equalp normalized
          (normalize-probabilities a
                                   :element-type 'double-float
                                   :result nil))
      (assert-equalp a normalized)
      (assert-false (equalp a a-copy)))))

(deftest arithmetic-rounding (arithmetic-tests)
  (assert-equalp '(25 2) (multiple-value-list (floor* 27 5)))
  (assert-equalp '(26 1) (multiple-value-list (floor* 27 5 1)))
  (assert-equalp '(30 -3) (multiple-value-list (ceiling* 27 5)))
  (assert-equalp '(31 -4) (multiple-value-list (ceiling* 27 5 1)))
  (assert-equalp '(25 2) (multiple-value-list (round* 27 5)))
  (assert-equalp '(29 -2) (multiple-value-list (round* 27 5 -1)))
  (assert-equalp '(-25 -2) (multiple-value-list (truncate* -27 5)))
  (assert-equalp '(-24 -3) (multiple-value-list (truncate* -27 5 1))))
