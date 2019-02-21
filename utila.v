(*
  This library contains useful functions for generating Kami
  expressions.
 *)
Require Import Syntax.
Require Import List.
Import ListNotations.

Section utila.

  Open Scope kami_expr.

  Section defs.

    Variable ty : Kind -> Type.

    (* I. Kami Expression Definitions *)

    Definition utila_opt_pkt
               (k : Kind)
               (x : k @# ty)
               (valid : Bool @# ty)
      :  Maybe k @# ty
      := STRUCT {
             "valid" ::= valid;
             "data"  ::= x
           }.

    Definition utila_all
      :  list (Bool @# ty) -> Bool @# ty
      := fold_right (fun x acc => x && acc) ($$true).

    Definition utila_any
      :  list (Bool @# ty) -> Bool @# ty
      := fold_right (fun x acc => x || acc) ($$false).

    (* Kami Monadic Definitions *)

    Structure utila_monad_type := utila_monad {
                                      utila_m
                                      : Kind -> Type;

                                      utila_mbind
                                      : forall (j k : Kind), utila_m j -> (ty j -> utila_m k) -> utila_m k;

                                      utila_munit
                                      : forall k : Kind, k @# ty -> utila_m k
                                    }.

    Definition utila_act_monad
      :  utila_monad_type
      := utila_monad (ActionT ty) (fun j k => @LetAction ty k j) (@Return ty).

    Section monad_functions.

      Variable monad : utila_monad_type.

      Let m := utila_m monad.

      Let mbind := utila_mbind monad.

      Let munit := utila_munit monad.

      Definition utila_mopt_pkt
                 (k : Kind)
                 (x : k @# ty)
                 (valid : Bool @# ty)
        :  m (Maybe k)
        := munit (utila_opt_pkt x valid).

      Definition utila_mfoldr
                 (j k : Kind)
                 (f : j @# ty -> k @# ty -> k @# ty)
                 (init : k @# ty)
        :  list (m j) -> (m k)
        := fold_right
             (fun (x_expr : m j)
                  (acc_expr : m k)
              => mbind k x_expr (fun x : ty j =>
                                   mbind k acc_expr (fun acc : ty k =>
                                                       munit
                                                         (f (Var ty (SyntaxKind j) x)
                                                            (Var ty (SyntaxKind k) acc)))))
             (munit init).

      Definition utila_mall
        :  list (m Bool) -> m Bool
        := utila_mfoldr (fun x acc => x && acc) (Const ty true).

      Definition utila_many
        :  list (m Bool) -> m Bool
        := utila_mfoldr (fun x acc => x || acc) (Const ty false).

    End monad_functions.

    (* II. Kami Let Expression Definitions *)

    Definition utila_expr_monad
      :  utila_monad_type
      := utila_monad (LetExprSyntax ty) (fun j k => @LetE ty k j) (@NormExpr ty).

    Definition utila_expr_opt_pkt := utila_mopt_pkt utila_expr_monad.

    Definition utila_expr_foldr := utila_mfoldr utila_expr_monad.

    Definition utila_expr_all := utila_mall utila_expr_monad.

    Definition utila_expr_any := utila_many utila_expr_monad.

    (*
  Accepts a Kami predicate [f] and a list of Kami let expressions
  that represent values, and returns a Kami let expression that
  outputs the value that satisfies f.

  Note: [f] must only return true for exactly one value in
  [xs_exprs].
     *)
    Definition utila_expr_find
               (k : Kind)
               (f : k @# ty -> Bool @# ty)
               (xs_exprs : list (k ## ty))
      :  k ## ty
      := LETE y
         :  Bit (size k)
                <- (utila_expr_foldr
                      (fun x acc => ((ITE (f x) (pack x) ($0)) | acc))
                      ($0)
                      xs_exprs);
           RetE (unpack k (#y)).

    Arguments utila_expr_find {k} f xs_exprs.

    (*
  Accepts a list of Maybe packets and returns the packet whose
  valid flag equals true.

  Note: exactly one of the packets must be valid.
     *)
    Definition utila_expr_find_pkt
               (k : Kind)
               (pkt_exprs : list (Maybe k ## ty))
      :  Maybe k ## ty
      := utila_expr_find
           (fun (pkt : Maybe k @# ty)
            => pkt @% "valid")
           pkt_exprs.

  End defs.

  (* IV. Correctness Proofs *)

  Section ver.

    Local Notation "{{ X }}" := (evalExpr X).

    Local Notation "X ==> Y" := (evalExpr X = Y) (at level 75).

    Local Notation "==> Y" := (fun x => evalExpr x = Y) (at level 75).

    Let utila_is_true (x : Bool @# type) := x ==> true.

    Theorem utila_all_correct
      :  forall xs : list (Bool @# type),
        utila_all xs ==> true <-> Forall utila_is_true xs.
    Proof
      fun xs
      => conj
           (list_ind
              (fun ys => utila_all ys ==> true -> Forall utila_is_true ys)
              (fun _ => Forall_nil utila_is_true)
              (fun y0 ys
                   (F : utila_all ys ==> true -> Forall utila_is_true ys)
                   (H : utila_all (y0 :: ys) ==> true)
               => let H0
                      :  y0 ==> true /\ utila_all ys ==> true
                      := andb_prop {{y0}} {{utila_all ys}} H in
                  Forall_cons y0 (proj1 H0) (F (proj2 H0)))
              xs)
           (@Forall_ind
              (Bool @# type)
              (==> true)
              (fun ys => utila_all ys ==> true)
              (eq_refl true)
              (fun y0 ys
                   (H : y0 ==> true)
                   (H0 : Forall utila_is_true ys)
                   (F : utila_all ys ==> true)
               => andb_true_intro (conj H F))
              xs).

    Theorem utila_any_correct
      :  forall xs : list (Bool @# type),
        utila_any xs ==> true <-> Exists utila_is_true xs.
    Proof
      fun xs
      => conj
           (list_ind
              (fun ys => utila_any ys ==> true -> Exists utila_is_true ys)
              (fun H : false = true
               => False_ind
                    (Exists utila_is_true nil)
                    (diff_false_true H))
              (fun y0 ys
                   (F : utila_any ys ==> true -> Exists utila_is_true ys)
                   (H : utila_any (y0 :: ys) ==> true)
               => let H0
                      :  y0 ==> true \/ utila_any ys ==> true
                      := orb_prop {{y0}} {{utila_any ys}} H in
                  match H0 with
                  | or_introl H1
                    => Exists_cons_hd utila_is_true y0 ys H1 
                  | or_intror H1
                    => Exists_cons_tl y0 (F H1)
                  end)
              xs)
           (@Exists_ind 
              (Bool @# type)
              (==> true)
              (fun ys => utila_any ys ==> true)
              (fun y0 ys
                   (H : y0 ==> true)
               => eq_ind
                    true
                    (fun z : bool => (orb z {{utila_any ys}}) = true)
                    (orb_true_l {{utila_any ys}})
                    {{y0}}
                    (eq_sym H))
              (fun y0 ys
                   (H : Exists utila_is_true ys)
                   (F : utila_any ys ==> true)
               => eq_ind_r
                    (fun z => orb {{y0}} z = true)
                    (orb_true_r {{y0}})
                    F)
              xs).

  End ver.

  (* III. Denotational semantics for monadic expressions. *)

  Structure utila_sem_type := utila_sem {
                                  utila_sem_m
                                  : utila_monad_type type;

                                  utila_sem_interp
                                  : forall k : Kind, utila_m utila_sem_m k -> type k;

                                  utila_sem_interp_foldr_nil_correct
                                  :  forall (j k : Kind)
                                            (f : j @# type -> k @# type -> k @# type)
                                            (init : k @# type)
                                            (x0 : utila_m utila_sem_m j)
                                            (xs : list (utila_m utila_sem_m j)),
                                      (utila_sem_interp k
                                                        (utila_mfoldr utila_sem_m f init nil) =
                                       evalExpr init);

                                  utila_sem_interp_foldr_cons_correct
                                  :  forall (j k : Kind)
                                            (f : j @# type -> k @# type -> k @# type)
                                            (init : k @# type)
                                            (x0 : utila_m utila_sem_m j)
                                            (xs : list (utila_m utila_sem_m j)),
                                      (utila_sem_interp k
                                                        (utila_mfoldr utila_sem_m f init (x0 :: xs)) =
                                       (evalExpr
                                          (f
                                             (Var type (SyntaxKind j)
                                                  (utila_sem_interp j x0))
                                             (Var type (SyntaxKind k)
                                                  (utila_sem_interp k
                                                                    (utila_mfoldr utila_sem_m f init xs))))))
                                }.

  Arguments utila_sem_interp u {k}.

  Section monad_ver.

    Variable sem : utila_sem_type.

    Let m
      :  utila_monad_type type
      := utila_sem_m sem.

    Let M
      :  Kind -> Type
      := utila_m (utila_sem_m sem).

    Local Notation "A || B @ X 'by' E"
      := (eq_ind_r (fun X => B) A E) (at level 40, left associativity).

    Local Notation "A || B @ X 'by' <- H"
      := (eq_ind_r (fun X => B) A (eq_sym H)) (at level 40, left associativity).

    Local Notation "{{ X }}" := (evalExpr X).

    Local Notation "[[ X ]]" := (utila_sem_interp sem X).

    Local Notation "#[[ X ]]" := (Var type (SyntaxKind _) [[X]]) (only parsing) : kami_expr_scope.

    Local Notation "==> Y" := (fun x => utila_sem_interp sem x = Y) (at level 75).

    Let utila_is_true (x : M Bool) := [[x]] = true.

  End monad_ver.

  Section expr_ver.

    Local Notation "A || B @ X 'by' E"
      := (eq_ind_r (fun X => B) A E) (at level 40, left associativity).

    Local Notation "A || B @ X 'by' <- H"
      := (eq_ind_r (fun X => B) A (eq_sym H)) (at level 40, left associativity).

    Local Notation "{{ X }}" := (evalExpr X).

    Local Notation "[[ X ]]" := (evalLetExpr X).

    Local Notation "#[[ X ]]" := (Var type (SyntaxKind _) [[X]]) (only parsing) : kami_expr_scope.

    Local Notation "X ==> Y" := (evalLetExpr X = Y) (at level 75).

    Local Notation "==> Y" := (fun x => evalLetExpr x = Y) (at level 75).

    Let utila_is_true (x : Bool ## type) := x ==> true.

    Theorem utila_expr_foldr_correct_nil
      :  forall (j k : Kind) (f : j @# type -> k @# type -> k @# type) (init : k @# type),
        utila_expr_foldr f init nil ==> {{init}}.
    Proof
      fun j k f init
      => eq_refl ({{init}}).

    Theorem utila_expr_foldr_correct_cons
      :  forall (j k : Kind)
                (f : j @# type -> k @# type -> k @# type)
                (init : k @# type)
                (x0 : j ## type) (xs : list (j ## type)),
        [[utila_expr_foldr f init (x0 :: xs)]] =
        {{ f (Var type (SyntaxKind j) [[x0]])
             (Var type (SyntaxKind k) [[utila_expr_foldr f init xs]]) }}.
    Proof
      fun (j k : Kind)
          (f : j @# type -> k @# type -> k @# type)
          (init : k @# type)
          (x0 : j ## type)
          (xs : list (j ## type))
      => eq_refl.

    Theorem utila_expr_all_correct
      :  forall xs : list (Bool ## type),
        utila_expr_all xs ==> true <-> Forall utila_is_true xs.
    Proof
      fun xs
      => conj
           (list_ind
              (fun ys => utila_expr_all ys ==> true -> Forall utila_is_true ys)
              (fun _ => Forall_nil utila_is_true)
              (fun y0 ys
                   (F : utila_expr_all ys ==> true -> Forall utila_is_true ys)
                   (H : utila_expr_all (y0 :: ys) ==> true)
               => let H0
                      :  y0 ==> true /\ utila_expr_all ys ==> true
                      := andb_prop [[y0]] [[utila_expr_all ys]] H in
                  Forall_cons y0 (proj1 H0) (F (proj2 H0)))
              xs)
           (@Forall_ind
              (Bool ## type)
              utila_is_true
              (fun ys => utila_expr_all ys ==> true)
              (eq_refl true)
              (fun y0 ys
                   (H : y0 ==> true)
                   (H0 : Forall utila_is_true ys)
                   (F : utila_expr_all ys ==> true)
               => andb_true_intro (conj H F))
              xs).

    Theorem utila_expr_any_correct
      :  forall xs : list (Bool ## type),
        utila_expr_any xs ==> true <-> Exists utila_is_true xs.
    Proof
      fun xs
      => conj
           (list_ind
              (fun ys => utila_expr_any ys ==> true -> Exists utila_is_true ys)
              (fun H : false = true
               => False_ind
                    (Exists utila_is_true nil)
                    (diff_false_true H))
              (fun y0 ys
                   (F : utila_expr_any ys ==> true -> Exists utila_is_true ys)
                   (H : utila_expr_any (y0 :: ys) ==> true)
               => let H0
                      :  y0 ==> true \/ utila_expr_any ys ==> true
                      := orb_prop [[y0]] [[utila_expr_any ys]] H in
                  match H0 with
                  | or_introl H1
                    => Exists_cons_hd utila_is_true y0 ys H1 
                  | or_intror H1
                    => Exists_cons_tl y0 (F H1)
                  end)
              xs)
           (@Exists_ind 
              (Bool ## type)
              (==> true)
              (fun ys => utila_expr_any ys ==> true)
              (fun y0 ys
                   (H : y0 ==> true)
               => eq_ind
                    true
                    (fun z : bool => (orb z [[utila_expr_any ys]]) = true)
                    (orb_true_l [[utila_expr_any ys]])
                    [[y0]]
                    (eq_sym H))
              (fun y0 ys
                   (H : Exists utila_is_true ys)
                   (F : utila_expr_any ys ==> true)
               => eq_ind_r
                    (fun z => orb [[y0]] z = true)
                    (orb_true_r [[y0]])
                    F)
              xs).

    Lemma utila_ite_l
      :  forall (k : Kind) (x y : k @# type) (p : Bool @# type),
        {{p}} = true ->
        {{ITE p x y}} = {{x}}.
    Proof
      fun k x y p H
      => eq_ind
           true
           (fun q : bool => (if q then {{x}} else {{y}}) = {{x}})
           (eq_refl {{x}})
           {{p}}
           (eq_sym H).

    Lemma utila_ite_r
      :  forall (k : Kind) (x y : k @# type) (p : Bool @# type),
        {{p}} = false ->
        {{ITE p x y}} = {{y}}.
    Proof
      fun k x y p H
      => eq_ind
           false
           (fun q : bool => (if q then {{x}} else {{y}}) = {{y}})
           (eq_refl {{y}})
           {{p}}
           (eq_sym H).

    (*
  The following section proves that the utila_expr_find function
  is correct. To prove, this result we make three four intuitive
  conjectures and prove two lemmas about the expressions produced
  by partially reducing utila_expr_find.
     *)
    Section utila_expr_find.

      (* The clauses used in Kami switch expressions. *)
      Let case (k : Kind) (f : k @# type -> Bool @# type) (x : k @# type) (acc : Bit (size k) @# type)
      :  Bit (size k) @# type
        := (ITE (f x) (pack x) ($ 0) | acc).

      Conjecture unpack_pack
        : forall (k : Kind)
                 (x : k ## type),
          {{unpack k
                   (Var type (SyntaxKind (Bit (size k)))
                        {{pack (Var type (SyntaxKind k) [[x]])}})}} =  
          [[x]].

      Conjecture kami_exprs_eq_dec
        :  forall (k : Kind) (x y : k ## type),
          {x = y} + {x <> y}.

      Lemma kami_in_dec
        :  forall (k : Kind) (x : k ## type) (xs : list (k ## type)),
          {In x xs} + {~ In x xs}.
      Proof
        fun k x xs
        => in_dec (@kami_exprs_eq_dec k) x xs.

      (*
  Note: submitted a pull request to the bbv repo to include this
  lemma in Word.v
       *)
      Lemma wor_idemp
        :  forall (n : nat) (x0 : word n), x0 ^| x0 = x0.
      Proof.
        (intros).
        (induction x0).
        reflexivity.
        (rewrite <- IHx0 at 3).
        (unfold wor).
        (simpl).
        (rewrite orb_diag).
        reflexivity.
      Qed.

      Lemma utila_expr_find_lm0
        :  forall (k : Kind)
                  (f : k @# type -> Bool @# type)
                  (init : Bit (size k) @# type)
                  (x0 : k ## type)
                  (xs : list (k ## type)),
          {{f (Var type (SyntaxKind k) [[x0]])}} = false ->
          [[utila_expr_foldr (case f) init (x0 :: xs)]] =
          [[utila_expr_foldr (case f) init xs]].
      Proof.
        (intros).
        (unfold evalLetExpr at 1).
        (unfold utila_expr_foldr at 1).
        (unfold utila_mfoldr).
        (intros).
        (simpl).
        (rewrite wor_wzero).
        (fold evalLetExpr).
        (fold utila_expr_foldr).
        (rewrite H).
        (rewrite wor_wzero).
        (unfold utila_expr_foldr).
        (unfold utila_mfoldr).
        (unfold utila_mbind).
        (simpl).
        reflexivity.
      Qed.

      Lemma utila_expr_find_lm1
        :  forall (k : Kind)
                  (f : k @# type -> Bool @# type)
                  (init : Bit (size k) @# type)
                  (xs : list (k ## type)),
          (forall x, In x xs -> {{f #[[x]]}} = false) ->
          [[utila_expr_foldr (case f) init xs]] = {{init}}.
      Proof
        fun (k : Kind)
            (f : k @# type -> Bool @# type)
            (init : Bit (size k) @# type)
        => list_ind
             (fun xs
              => (forall x, In x xs -> {{f #[[x]]}} = false) ->
                 [[utila_expr_foldr (case f) init xs]] = {{init}})
             (fun _
              => utila_expr_foldr_correct_nil (case f) init)
             (fun x0 xs
                  (F : (forall x, In x xs -> {{f #[[x]]}} = false) ->
                       [[utila_expr_foldr (case f) init xs]] = {{init}})
                  (H : forall x, In x (x0 :: xs) -> {{f #[[x]]}} = false)
              => let H0
                     :  forall x, In x xs -> {{f #[[x]]}} = false
                     := fun x H0
                        => H x (or_intror (x0 = x) H0) in
                 let H1
                     :  [[utila_expr_foldr (case f) init xs]] = {{init}}
                     := F H0 in
                 let H2
                     :  {{f #[[x0]]}} = false
                     := H x0 (or_introl (In x0 xs) (eq_refl x0)) in
                 utila_expr_find_lm0 f init x0 xs H2
                 || [[utila_expr_foldr (case f) init (x0 :: xs)]] = a
                                                                      @a by <- H1).

      (*
  This proof proceeds using proof by cases when [xs = y0 :: ys].
  There are four cases, either [x = y0] or [x <> y0] and either
  [In x ys] or [~ In x ys]. If [x = y0] then [{{case f y0}} = {{pack
  x0}}]. Otherwise [{{case f y0}} = {{$0}}]. Similarly, when [x]
  is in [ys], [[[utila_expr_fold _ _ ys]] = {{pack x}}]. Otherwise,
  it equals [{{$0}}]. The only case where the result would not
  equal [{{pack x}}] is when [y0 <> x] and [~ In x ys]. But this
  contradicts the assumption that [x] is in [(y0::ys)]. Hence, we
  conclude that [[[utila_expr_foldr _ _ (y0 :: ys)]] = {{pack x}}].
       *)
      Lemma utila_expr_find_lm2
        :  forall (k : Kind)
                  (f : k @# type -> Bool @# type)
                  (x : k ## type)
                  (xs : list (k ## type)),
          (unique (fun x => In x xs /\ {{f #[[x]]}} = true) x) ->
          [[utila_expr_foldr (case f) ($0) xs]] =
          {{pack #[[x]]}}.
      Proof
        fun (k : Kind)
            (f : k @# type -> Bool @# type)
            (x : k ## type)
        => list_ind
             (fun xs
              => unique (fun x => In x xs /\ {{f #[[x]]}} = true) x ->
                 [[utila_expr_foldr (case f) ($0) xs]] =
                 {{pack #[[x]]}})
             (* I. contradictory case. *)
             (fun H
              => False_ind _
                           (proj1 (proj1 H)))
             (* II. *)
             (fun x0 xs
                  (F : unique (fun x => In x xs /\ {{f #[[x]]}} = true) x ->
                       [[utila_expr_foldr (case f) ($0) xs]] =
                       {{pack #[[x]]}})
                  (H : unique (fun x => In x (x0 :: xs) /\ {{f #[[x]]}} = true) x)
              => let fx_true
                     :  {{f #[[x]]}} = true
                     := proj2 (proj1 H) in
                 let eq_x
                     :  forall y, (In y (x0 ::xs) /\ {{f #[[y]]}} = true) -> x = y
                     := proj2 H in
                 let eq_pack_x
                     :  In x xs ->
                        [[utila_expr_foldr (case f) ($0) xs]] =
                        {{pack #[[x]]}}
                     := fun in_x_xs
                        => F (conj 
                                (conj in_x_xs fx_true)
                                (fun y (H0 : In y xs /\ {{f #[[y]]}} = true)
                                 => eq_x y
                                         (conj
                                            (or_intror (x0 = y) (proj1 H0))
                                            (proj2 H0)))) in
                 sumbool_ind
                   (fun _
                    => [[utila_expr_foldr (case f) ($0) (x0 :: xs)]] =
                       {{pack #[[x]]}})
                   (* II.A *)
                   (fun eq_x0_x : x0 = x
                    => let fx0_true
                           :  {{f #[[x0]]}} = true
                           := fx_true || {{f #[[a]]}} = true @a by eq_x0_x in
                       let red0
                           :  [[utila_expr_foldr (case f) ($0) (x0 :: xs)]] =
                              {{pack #[[x]]}} ^|
                                              [[utila_expr_foldr (case f) _ xs]]
                           := utila_expr_foldr_correct_cons (case f) ($0) x0 xs
                              || _ = a ^| [[utila_expr_foldr (case f) _ xs]]
                                       @a by <- wor_wzero
                                                (if {{f #[[x0]]}}
                                                 then {{pack #[[x0]]}}
                                                 else $0)
                                             || _ = (if a : bool then _ else _) ^| _
                                                                                @a by <- fx0_true 
                                                                                      || _ = {{pack #[[a]]}} ^| _
                                                                                                             @a by <- eq_x0_x in
                       sumbool_ind
                         (fun _
                          => [[utila_expr_foldr (case f) ($0) (x0 :: xs)]] =
                             {{pack #[[x]]}})
                         (* II.A.1 *)
                         (fun in_x_xs : In x xs
                          => red0
                             || _ = _ ^| a
                                      @a by <- eq_pack_x in_x_xs
                                            || _ = a
                                                     @a by <- wor_idemp {{pack #[[x]]}})
                         (* II.A.2 *)
                         (fun not_in_x_xs : ~ In x xs
                          => let eq_0
                                 :  [[utila_expr_foldr (case f) ($0) xs]] = {{$0}}
                                 := utila_expr_find_lm1
                                      f ($0) xs
                                      (fun y (in_y_xs : In y xs)
                                       => not_true_is_false {{f #[[y]]}}
                                                            (fun fy_true : {{f #[[y]]}} = true
                                                             => not_in_x_xs
                                                                  (in_y_xs
                                                                   || In a xs
                                                                         @a by eq_x y (conj (or_intror _ in_y_xs) fy_true)))) in
                             red0
                             || _ = _ ^| a
                                      @a by <- eq_0
                                            || _ = a
                                                     @a by <- wzero_wor {{pack #[[x]]}})
                         (kami_in_dec x xs))
                   (* II.B *)
                   (fun not_eq_x0_x : x0 <> x
                    => let fx0_false
                           :  {{f #[[x0]]}} = false
                           := not_true_is_false {{f #[[x0]]}}
                                                (fun fx0_true : {{f #[[x0]]}} = true
                                                 => not_eq_x0_x
                                                      (eq_sym (eq_x x0 (conj (or_introl _ eq_refl) fx0_true)))) in
                       (* prove partial reduction - assume that x0 <> x *)
                       sumbool_ind
                         (fun _
                          => [[utila_expr_foldr (case f) ($0) (x0 :: xs)]] =
                             {{pack #[[x]]}})
                         (* II.B.1 *)
                         (fun in_x_xs : In x xs
                          => utila_expr_find_lm0 f ($0) x0 xs fx0_false
                             || _ = a @a by <- eq_pack_x in_x_xs)
                         (* II.B.2 contradictory case - x must be in x0 :: xs. *)
                         (fun not_in_x_xs : ~ In x xs
                          => False_ind _
                                       (or_ind
                                          not_eq_x0_x
                                          not_in_x_xs
                                          (proj1 (proj1 H))))
                         (kami_in_dec x xs))
                   (kami_exprs_eq_dec x0 x)).       

      Theorem utila_expr_find_correct
        : forall (k : Kind)
                 (f : k @# type -> Bool @# type)
                 (xs : list (k ## type))
                 (x : k ## type),
          (unique (fun y => In y xs /\ {{f #[[y]]}} = true) x) ->
          [[utila_expr_find f xs]] = [[x]].
      Proof.
        (intros).
        (unfold utila_expr_find).
        (unfold evalLetExpr at 1).
        (fold evalLetExpr).
        replace
          (fun (x0 : Expr type (SyntaxKind k))
               (acc : Expr type (SyntaxKind (Bit (size k))))
           => (IF f x0 then pack x0 else Const type ($0)%word | acc))
          with (case f).
        (rewrite (utila_expr_find_lm2 f xs H)).
        (apply unpack_pack).
        (unfold case).
        reflexivity.
      Qed.

    End utila_expr_find.

    Theorem utila_expr_find_pkt_correct
      :  forall (k : Kind)
                (xs : list (Maybe k ## type))
                (x : Maybe k ## type),
        (unique (fun y => In y xs /\ {{#[[y]] @% "valid"}} = true) x) ->
        [[utila_expr_find_pkt xs]] = [[x]].
    Proof
      fun k xs
      => utila_expr_find_correct
           (fun y : Maybe k @# type => y @% "valid") xs.

  End expr_ver.

  Variable ty : Kind -> Type.

  (* Kami Let Expressions *)

  (* Kami Actions *)

  Open Scope kami_action.

  Definition utila_acts_opt_pkt
             (k : Kind)
             (x : k @# ty)
             (valid : Bool @# ty)
    :  ActionT ty (Maybe k)
    := Ret (utila_opt_pkt x valid).

  Definition utila_acts_foldr
             (j k : Kind)
             (f : j @# ty -> k @# ty -> k @# ty)
             (init : k @# ty)
    :  list (ActionT ty j) -> ActionT ty k
    := fold_right
         (fun (x_act : ActionT ty j)
              (acc_act : ActionT ty k)
          => LETA x   : j <- x_act;
               LETA acc : k <- acc_act;
               Ret (f (#x) (#acc)))
         (Ret init).

  Definition utila_acts_find
             (k : Kind) 
             (f : k @# ty -> Bool @# ty)
             (xs_acts : list (ActionT ty k))
    :  ActionT ty k
    := LETA y
       :  Bit (size k)
              <- utila_acts_foldr
              (fun x acc => ((ITE (f x) (pack x) ($0)) | acc))
              ($0)
              xs_acts;
         Ret (unpack k (#y)).

  Definition utila_acts_find_pkt
             (k : Kind)
             (pkt_acts : list (ActionT ty (Maybe k)))
    :  ActionT ty (Maybe k)
    := utila_acts_find
         (fun pkt : Maybe k @# ty
          => pkt @% "valid")
         pkt_acts.

  Close Scope kami_action.

  Close Scope kami_expr.

End utila.
