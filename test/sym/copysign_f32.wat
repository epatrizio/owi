;; sign(y)*abs(x) == copy_sign(x,y)

(module
  (import "symbolic" "f32_symbol" (func $f32_symbol (result f32)))
  (import "symbolic" "assert" (func $assert_i32 (param i32)))
  (import "symbolic" "assume" (func $assume_i32 (param i32)))

  (func $start
    (local $x f32)
    (local $y f32)

    (local.set $x (call $f32_symbol))
    (local.set $y (call $f32_symbol))

    (call $assume_i32   ;; 0 < y < 42
      (i32.and
        (f32.gt (local.get $y) (f32.const 0))
        (f32.lt (local.get $y) (f32.const 42))))
    (call $assume_i32   ;; -42 < x < 42
      (i32.and
        (f32.gt (local.get $x) (f32.const -42))
        (f32.lt (local.get $x) (f32.const 42))))
    
    (call $assert_i32   ;; y>0 => abs(x) == copy_sign(x,y)
      (f32.eq
        (f32.abs (local.get $x))
        (f32.copysign (local.get $x) (local.get $y))))

    (call $assert_i32   ;; y<0 => -abs(x) == copy_sign(x,y)
      (f32.eq
        (f32.mul (f32.const -1) (f32.abs (local.get $x)))
        (f32.copysign (local.get $x) (f32.mul (f32.const -1) (local.get $y)))))
  )

  (start $start)
)
