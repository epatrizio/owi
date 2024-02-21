;; sign(y)*abs(x) == copy_sign(x,y)

(module
  (import "symbolic" "f64_symbol" (func $f64_symbol (result f64)))
  (import "symbolic" "assert" (func $assert_i32 (param i32)))
  (import "symbolic" "assume" (func $assume_i32 (param i32)))

  (func $start
    (local $x f64)
    (local $y f64)

    (local.set $x (call $f64_symbol))
    (local.set $y (call $f64_symbol))

    (call $assume_i32   ;; 0 < y < 42
      (i32.and
        (f64.gt (local.get $y) (f64.const 0))
        (f64.lt (local.get $y) (f64.const 42))))
    (call $assume_i32   ;; -42 < x < 42
      (i32.and
        (f64.gt (local.get $x) (f64.const -42))
        (f64.lt (local.get $x) (f64.const 42))))
    
    (call $assert_i32   ;; y>0 => abs(x) == copy_sign(x,y)
      (f64.eq
        (f64.abs (local.get $x))
        (f64.copysign (local.get $x) (local.get $y))))

    (call $assert_i32   ;; y<0 => -abs(x) == copy_sign(x,y)
      (f64.eq
        (f64.mul (f64.const -1) (f64.abs (local.get $x)))
        (f64.copysign (local.get $x) (f64.mul (f64.const -1) (local.get $y)))))
  )

  (start $start)
)
