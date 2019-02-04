(*
Require Import Syntax Rtl.

Set Implicit Arguments.
Set Asymmetric Patterns.

Local Open Scope string.

Local Notation nil_nat := (nil: list nat).

Definition getRegActionRead a s := (a ++ "#" ++ s ++ "#_read", nil_nat).
Definition getRegActionWrite a s := (a ++ "#" ++ s ++ "#_tempwrite", nil_nat).
Definition getRegActionFinalWrite a s := (a ++ "#" ++ s ++ "#_write", nil_nat).
Definition getRegActionEn a s := (a ++ "#" ++ s ++ "#_en", nil_nat).

Definition getRegRead s := (s ++ "#_read", nil_nat).
Definition getRegWrite s := (s ++ "#_write", nil_nat).

Definition getMethActionArg a f := (a ++ "#" ++ f ++ "#_argument", nil_nat).
Definition getMethActionEn a f := (a ++ "#" ++ f ++ "#_enable", nil_nat).

Definition getMethRet f := (f ++ "#_return", nil_nat).
Definition getMethArg f := (f ++ "#_argument", nil_nat).
Definition getMethEn f := (f ++ "#_enable", nil_nat).
Definition getMethGuard f := (f ++ "#_guard", nil_nat).

Definition getActionGuard r := (r ++ "#_guard", nil_nat).
Definition getActionEn r := (r ++ "#_enable", nil_nat).

Local Close Scope string.

Local Notation cast k' v := v (only parsing).


Section Compile.
  Variable name: string.

  Fixpoint convertExprToRtl k (e: Expr (fun _ => list nat) (SyntaxKind k)) :=
    match e in Expr _ (SyntaxKind k) return RtlExpr k with
      | Var k' x' =>   match k' return
                             (forall x,
                                match k' return (Expr (fun _ => list nat) k' -> Set) with
                                  | SyntaxKind k => fun _ => RtlExpr k
                                  | NativeKind _ => fun _ => IDProp
                                end (Var (fun _ => list nat) k' x))
                       with
                         | SyntaxKind k => fun x => RtlReadWire k (name, x)
                         | NativeKind t => fun _ => idProp
                       end x'
      | Const k x => RtlConst x
      | UniBool x x0 => RtlUniBool x (@convertExprToRtl _ x0)
      | CABool x x0 => RtlCABool x (map (@convertExprToRtl _) x0)
      | UniBit n1 n2 x x0 => RtlUniBit x (@convertExprToRtl _ x0)
      | CABit n x x0 => RtlCABit x (map (@convertExprToRtl _) x0)
      | BinBit n1 n2 n3 x x0 x1 => RtlBinBit x (@convertExprToRtl _ x0) (@convertExprToRtl _ x1)
      | BinBitBool n1 n2 x x0 x1 => RtlBinBitBool x (@convertExprToRtl _ x0) (@convertExprToRtl _ x1)
      | Eq k e1 e2 => RtlEq (@convertExprToRtl _ e1) (@convertExprToRtl _ e2)
      | ReadStruct n fk fs e i => @RtlReadStruct n fk fs (@convertExprToRtl _ e) i
      | BuildStruct n fk fs fv => @RtlBuildStruct n fk fs (fun i => @convertExprToRtl _ (fv i))
      | ReadArray n k arr idx => @RtlReadArray n k (@convertExprToRtl _ arr) (@convertExprToRtl _ idx)
      | ReadArrayConst n k arr idx => @RtlReadArrayConst n k (@convertExprToRtl _ arr) idx
      | BuildArray n k farr => @RtlBuildArray n k (fun i => @convertExprToRtl _ (farr i))
      | ITE k' x x0' x1' =>
        match k' return
              (forall x0 x1,
                 match k' return (Expr (fun _ => list nat) k' -> Set) with
                   | SyntaxKind k => fun _ => RtlExpr k
                   | NativeKind _ => fun _ => IDProp
                 end (ITE x x0 x1))
        with
          | SyntaxKind k => fun x0 x1 => RtlITE (@convertExprToRtl _ x) (@convertExprToRtl _ x0) (@convertExprToRtl _ x1)
          | NativeKind t => fun _ _ => idProp
        end x0' x1'
    end.

  Local Definition inc ns := match ns with
                             | nil => nil
                             | x :: xs => S x :: xs
                             end.

  Axiom cheat: forall t, t.

  Fixpoint convertActionToRtl_noGuard k (a: ActionT (fun _ => list nat) k) startList retList :=
    match a in ActionT _ _ with
      | MCall meth k argExpr cont =>
        (name, startList, existT _ (snd k) (RtlReadWire (snd k) (getMethRet meth))) ::
        convertActionToRtl_noGuard (cont startList) (inc startList) retList
      | Return x => (name, retList, existT _ k (convertExprToRtl x)) :: nil
      | LetExpr k' expr cont =>
        match k' return Expr (fun _ => list nat) k' ->
                        (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (string * list nat * sigT RtlExpr) with
        | SyntaxKind k => fun expr cont => (name, startList, existT _ k (convertExprToRtl expr))
                                             ::
                                             convertActionToRtl_noGuard (cont startList) (inc startList)
                                             retList
        | _ => fun _ _ => nil
        end expr cont
      | LetAction k' a' cont =>
        convertActionToRtl_noGuard a' (0 :: startList) startList ++
        convertActionToRtl_noGuard (cont startList) (inc startList) retList
      | ReadNondet k' cont =>
        match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (string * list nat * sigT RtlExpr) with
        | SyntaxKind k => fun cont => (name, startList, existT _ k (convertExprToRtl
                                                                      (Const _ (getDefaultConst _))))
                                        ::
                                        convertActionToRtl_noGuard (cont startList) (inc startList) retList
        | _ => fun _ => nil
        end cont
      | ReadReg r k' cont =>
        match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (string * list nat * sigT RtlExpr) with
          | SyntaxKind k => fun cont => (name, startList,
                                         existT _ k (RtlReadWire k (getRegActionRead name r)))
                                          ::
                                          convertActionToRtl_noGuard (cont startList)
                                          (inc startList) retList
          | _ => fun _ => nil
        end cont
      | WriteReg r k' expr cont =>
        convertActionToRtl_noGuard cont startList retList
      | Assertion pred cont => convertActionToRtl_noGuard cont startList retList
      | Sys ls cont => convertActionToRtl_noGuard cont startList retList
      | IfElse pred ktf t f cont =>
        convertActionToRtl_noGuard t (0 :: startList) (startList) ++
        convertActionToRtl_noGuard f (0 :: inc startList) (inc startList) ++
          (name, inc (inc startList),
           existT _ ktf (RtlITE (convertExprToRtl pred) (RtlReadWire ktf (name, startList)) (RtlReadWire ktf (name, inc startList)))) ::
        convertActionToRtl_noGuard (cont (inc (inc startList))) (inc (inc (inc startList))) retList
        end.

  Fixpoint convertActionToRtl_guard k (a: ActionT (fun _ => list nat) k) startList:
    list (RtlExpr Bool) :=
    match a in ActionT _ _ with
      | MCall meth k argExpr cont =>
        RtlReadWire Bool (getActionGuard meth) ::
                    (convertActionToRtl_guard (cont startList) (inc startList))
      | LetExpr k' expr cont =>
        match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (RtlExpr Bool) with
        | SyntaxKind k => fun cont =>
                            convertActionToRtl_guard (cont startList) (inc startList)
        | _ => fun _ => nil
        end cont
      | ReadNondet k' cont =>
        match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (RtlExpr Bool) with
        | SyntaxKind k => fun cont =>
                            convertActionToRtl_guard (cont startList) (inc startList)
        | _ => fun _ => nil
        end cont
      | ReadReg r k' cont =>
        match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                        list (RtlExpr Bool) with
        | SyntaxKind k => fun cont =>
                            convertActionToRtl_guard (cont startList) (inc startList)
        | _ => fun _ => nil
        end cont
      | WriteReg r k' expr cont =>
        convertActionToRtl_guard cont startList
      | Assertion pred cont => convertExprToRtl pred ::
                                              (convertActionToRtl_guard cont startList)
      | Sys ls cont => convertActionToRtl_guard cont startList
      | Return x => nil
      | IfElse pred ktf t f cont =>
        let wc := convertActionToRtl_guard (cont (inc (inc startList))) (inc (inc (inc startList))) in
        let p := convertExprToRtl pred in
        match convertActionToRtl_guard t (0 :: startList), convertActionToRtl_guard f (0 :: inc startList) with
        | nil, nil => wc
        | e, nil => RtlCABool Or (RtlUniBool Neg p :: e) :: wc
        | nil, e => RtlCABool Or (p :: e) :: wc
        | e1, e2 => RtlITE p (RtlCABool And e1) (RtlCABool And e2) :: wc
        end
        (* (RtlITE (convertExprToRtl pred) (RtlCABool And *)
        (*                                            (convertActionToRtl_guard t (0 :: startList))) *)
        (*         (RtlCABool And (convertActionToRtl_guard f (0 :: inc startList)))) *)
        (*   :: *)
        (*   (convertActionToRtl_guard (cont (inc (inc startList))) *)
        (*                             (inc (inc (inc startList)))) *)
      | LetAction k' a' cont =>
        convertActionToRtl_guard a' (0 :: startList) ++
                                 convertActionToRtl_guard (cont startList) (inc startList)
    end.

  Definition convertActionToRtl_guardF k (a: ActionT (fun _ => list nat) k) startList :=
    RtlCABool And (convertActionToRtl_guard a startList).

  Definition invalidRtl k v :=
    ((STRUCT {
          "valid" ::= RtlConst false ;
          "data" ::= v
     })%rtl_expr : RtlExpr (Maybe k)).


  Definition conditionPair k (p: RtlExpr Bool) (e1 e2: (RtlExpr Bool * RtlExpr k)) :=
    (RtlITE p (fst e1) (fst e2), RtlITE p (snd e1) (snd e2)).
  Definition invalidPair k (v: RtlExpr k) := (RtlConst false, v).
             
  Section MethReg.
    Open Scope string.
    Section GetRegisterWrites.
      Variable reg: RegInitT.
      
      Definition regKind := match projT1 (snd reg) with
                            | SyntaxKind k => k
                            | _ => Void
                            end.
      
      Fixpoint getRegisterWrites k (a: ActionT (fun _ => list nat) k) (startList: list nat) : sum (RtlExpr Bool * RtlExpr regKind) (RtlExpr regKind) :=
        match a in ActionT _ _ with
        | MCall meth k argExpr cont =>
          @getRegisterWrites _ (cont startList) (inc startList)
        | Return x => inr (RtlConst (getDefaultConst _))
        | LetExpr k' expr cont =>
          match k' return Expr (fun _ => list nat) k' ->
                          (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun expr cont => @getRegisterWrites _ (cont startList) (inc startList)
          | _ => fun _ _ => inr (RtlConst (getDefaultConst _))
          end expr cont
        | LetAction k' a' cont =>
          let w1 := @getRegisterWrites _ a' (0 :: startList) in
          let w2 := @getRegisterWrites _ (cont startList) (inc startList) in
          match w1, w2 with
          | inr x, inr y => inr x
          | inr _, inl w2' => inl w2'
          | inl w1', inr _ => inl w1'
          | inl w1', inl w2' => inl (conditionPair (fst w2') w2' w1')%rtl_expr
          end
        | ReadNondet k' cont =>
          match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun cont => @getRegisterWrites _ (cont startList) (inc startList)
          | _ => fun _ => inr (RtlConst (getDefaultConst _))
          end cont
        | ReadReg r k' cont =>
          match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun cont => @getRegisterWrites _ (cont startList) (inc startList)
          | _ => fun _ => inr (RtlConst (getDefaultConst _))
          end cont
        | Assertion pred cont => @getRegisterWrites _ cont startList
        | Sys ls cont => @getRegisterWrites _ cont startList
        | IfElse pred ktf t f cont =>
          let p := convertExprToRtl pred in
          let wt := @getRegisterWrites _ t (0 :: startList) in
          let wf := @getRegisterWrites _ f (0 :: inc startList) in
          let wc := @getRegisterWrites _ (cont (inc (inc startList))) (inc (inc (inc startList))) in
          match wt, wf, wc with
          | inr x, inr y, inr z => inr x
          | inr x, inr y, inl wc' => inl wc'
          | inr x, inl wf', inr z => inl (conditionPair p (invalidPair (snd wf')) wf')
          | inl wt', inr y, inr z => inl (conditionPair p wt' (invalidPair (snd wt')))
          | inl wt', inl wf', inr z => inl (conditionPair p wt' wf')
          | inl wt', inr y, inl wc' => inl (conditionPair (fst wc') wc' (conditionPair p wt' (invalidPair (snd wt'))))%rtl_expr
          | inr x, inl wf', inl wc' => inl (conditionPair (fst wc') wc' (conditionPair p (invalidPair (snd wf')) wf'))%rtl_expr
          | inl wt', inl wf', inl wc' => inl (conditionPair (fst wc') wc'
                                                            (conditionPair p wt' wf'))%rtl_expr
          end
        | WriteReg r k' expr cont =>
          let wc := @getRegisterWrites _ cont startList in
          if string_dec r (fst reg)
          then
            match k' return Expr (fun _ => list nat) k' -> sum (RtlExpr Bool * RtlExpr regKind) (RtlExpr regKind) with
            | SyntaxKind k => fun expr =>
                                match Kind_dec regKind k with
                                | left pf => match pf in _ = Y return Expr _ (SyntaxKind Y) -> sum (RtlExpr Bool * RtlExpr regKind) (RtlExpr regKind) with
                                             | eq_refl => fun expr =>
                                                            match wc with
                                                            | inl wc' =>
                                                              inl (conditionPair (fst wc') wc'
                                                                                 (RtlCABool And (RtlReadWire Bool (getActionGuard name) :: RtlReadWire Bool (getActionEn name) :: nil),
                                                                                  convertExprToRtl expr)
                                                                  )%rtl_expr
                                                            | inr x => 
                                                              inl (RtlCABool And (RtlReadWire Bool (getActionGuard name) :: RtlReadWire Bool (getActionEn name) :: nil),
                                                                   convertExprToRtl expr
                                                                  )%rtl_expr
                                                            end
                                             end expr
                                | right _ => inl (RtlReadWire Bool
                                                              (("TYPES DONT MATCH FOR REGISTER " ++ r ++ " EXPECTED " ++ natToHexStr (size regKind) ++ " GOT " ++
                                                                                                 natToHexStr (size k)), nil),
                                                  RtlReadWire _ ("TYPES DONT MATCH FOR REGISTERS " ++ r ++ " EXPECTED " ++ natToHexStr (size regKind) ++ " GOT " ++
                                                                                                   natToHexStr (size k), nil))
                                end
            | _ => fun _ => wc
            end expr
          else wc
        end.
    End GetRegisterWrites.

    Section GetMethEns.
      Variable meth: Attribute Signature.
      
      Definition argKind := fst (snd meth).

      Fixpoint getMethEns k (a: ActionT (fun _ => list nat) k) (startList: list nat) : sum (RtlExpr Bool * RtlExpr argKind) (RtlExpr argKind) :=
        match a in ActionT _ _ with
        | Return x => inr (RtlConst (getDefaultConst _))
        | LetExpr k' expr cont =>
          match k' return Expr (fun _ => list nat) k' ->
                          (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun expr cont => @getMethEns _ (cont startList) (inc startList)
          | _ => fun _ _ => inr (RtlConst (getDefaultConst _))
          end expr cont
        | LetAction k' a' cont =>
          let w1 := @getMethEns _ a' (0 :: startList) in
          let w2 := @getMethEns _ (cont startList) (inc startList) in
          match w1, w2 with
          | inr x, inr y => inr x
          | inr x, inl w2' => inl w2'
          | inl w1', inr y => inl w1'
          | inl w1', inl w2' => inl (conditionPair (fst w2') w2' w1')%rtl_expr
          end
        | ReadNondet k' cont =>
          match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun cont => @getMethEns _ (cont startList) (inc startList)
          | _ => fun _ => inr (RtlConst (getDefaultConst _))
          end cont
        | ReadReg r k' cont =>
          match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) -> _ with
          | SyntaxKind k => fun cont => @getMethEns _ (cont startList) (inc startList)
          | _ => fun _ => inr (RtlConst (getDefaultConst _))
          end cont
        | Assertion pred cont => @getMethEns _ cont startList
        | Sys ls cont => @getMethEns _ cont startList
        | IfElse pred ktf t f cont =>
          let p := convertExprToRtl pred in
          let wt := @getMethEns _ t (0 :: startList) in
          let wf := @getMethEns _ f (0 :: inc startList) in
          let wc := @getMethEns _ (cont (inc (inc startList))) (inc (inc (inc startList))) in
          match wt, wf, wc with
          | inr x, inr y, inr z => inr x
          | inr x, inr y, inl wc' => inl wc'
          | inr x, inl wf', inr z => inl (conditionPair p (invalidPair (snd wf')) wf')
          | inl wt', inr y, inr z => inl (conditionPair p wt' (invalidPair (snd wt')))
          | inl wt', inl wf', inr z => inl (conditionPair p wt' wf')
          | inl wt', inr y, inl wc' => inl (conditionPair (fst wc') wc' (conditionPair p wt' (invalidPair (snd wt'))))%rtl_expr
          | inr x, inl wf', inl wc' => inl (conditionPair (fst wc') wc' (conditionPair p (invalidPair (snd wf')) wf'))%rtl_expr
          | inl wt', inl wf', inl wc' => inl (conditionPair (fst wc') wc'
                                                            (conditionPair p wt' wf'))%rtl_expr
          end
        | WriteReg r k' expr cont =>
          @getMethEns _ cont startList
        | MCall f k expr cont =>
          let wc := @getMethEns _ (cont startList) (inc startList) in
          if string_dec f (fst meth)
          then
            match Kind_dec argKind (fst k) with
            | left pf => match pf in _ = Y return Expr _ (SyntaxKind Y) -> sum (RtlExpr Bool * RtlExpr argKind) (RtlExpr argKind) with
                         | eq_refl => fun expr =>
                                        match wc with
                                        | inl wc' =>
                                          inl (conditionPair (fst wc') wc'
                                                             (RtlCABool And (RtlReadWire Bool (getActionGuard name) :: RtlReadWire Bool (getActionEn name) :: nil),
                                                              convertExprToRtl expr)
                                              )%rtl_expr
                                        | inr _ =>
                                          inl (RtlCABool And (RtlReadWire Bool (getActionGuard name) :: RtlReadWire Bool (getActionEn name) :: nil),
                                               convertExprToRtl expr
                                              )%rtl_expr
                                        end
                         end expr
            | right _ => inl (RtlReadWire Bool ("TYPES DONT MATCH FOR METHOD " ++ f, nil),
                              RtlReadWire _ ("", nil))
            end
          else wc
        end.

    End GetMethEns.
    Close Scope string.
  End MethReg.

  Definition convertRegsWrites regs k (a: ActionT (fun _ => list nat) k) startList :=
    map (fun reg =>
           let wc := getRegisterWrites reg a startList in
           match wc with
           | inl wc' =>
             (getRegActionFinalWrite name (fst reg), existT _ (regKind reg)
                                                            (RtlITE (fst wc')%rtl_expr (snd wc')%rtl_expr
                                                                    (RtlReadWire _ (getRegActionRead name (fst reg)))))
           | inr x => (getRegActionFinalWrite name (fst reg), existT _ (regKind reg) (RtlReadWire _ (getRegActionRead name (fst reg))))
           end
        ) regs.

  
  Definition getRtlDisp (d: SysT (fun _ => list nat)) :=
    match d with
    | DispString s => RtlDispString s
    | DispBool e f => RtlDispBool (@convertExprToRtl _ e) f
    | DispBit n e f => RtlDispBit (@convertExprToRtl _ e) f
    | DispStruct n fk fs e f => RtlDispStruct (@convertExprToRtl _ e) f
    | DispArray n k e f => RtlDispArray (@convertExprToRtl _ e) f
    | Finish => RtlFinish
    end.

  Fixpoint getRtlSys k (a: ActionT (fun _ => list nat) k) enable startList : list (RtlExpr Bool * list RtlSysT) :=
    match a in ActionT _ _ with
    | MCall meth k argExpr cont =>
      getRtlSys (cont startList) enable (inc startList)
    | LetExpr k' expr cont =>
      match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                      list (RtlExpr Bool * list RtlSysT) with
      | SyntaxKind k => fun cont =>
                          getRtlSys (cont startList) enable (inc startList)
      | _ => fun _ => nil
      end cont
    | LetAction k' a' cont =>
      getRtlSys a' enable (0 :: startList) ++
                getRtlSys (cont startList) enable (inc startList)
    | ReadNondet k' cont =>
      match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                      list (RtlExpr Bool * list RtlSysT) with
      | SyntaxKind k => fun cont =>
                          getRtlSys (cont startList) enable (inc startList)
      | _ => fun _ => nil
      end cont
    | ReadReg r k' cont =>
      match k' return (fullType (fun _ => list nat) k' -> ActionT (fun _ => list nat) k) ->
                      list (RtlExpr Bool * list RtlSysT) with
      | SyntaxKind k => fun cont =>
                          getRtlSys (cont startList) enable (inc startList)
      | _ => fun _ => nil
      end cont
    | WriteReg r k' expr cont =>
      getRtlSys cont enable startList
    | Assertion pred cont => getRtlSys cont (RtlCABool And
                                                       (convertExprToRtl pred :: enable :: nil))
                                       startList
    | Sys ls cont => (enable, map getRtlDisp ls) :: getRtlSys cont enable startList
    | Return x => nil
    | IfElse pred ktf t f cont =>
      getRtlSys t (RtlCABool And (convertExprToRtl pred :: enable :: nil)) (0 :: startList) ++
                getRtlSys f (RtlCABool And (convertExprToRtl (UniBool Neg pred) :: enable :: nil)) (0 :: inc startList) ++
                getRtlSys (cont (inc (inc startList))) enable (inc (inc (inc startList)))
    end.
End Compile.

Definition getRule m r :=
  find (fun x => getBool (string_dec r (fst x))) (getRules m).

Definition getMeth m r :=
  find (fun x => getBool (string_dec r (fst x))) (getMethods m).

Section ForMeth.
  Variable m: BaseModule.
  Variable meth: Attribute Signature.
  Open Scope string.

  Fixpoint getMethEnsOrder (order: list string) : sum (RtlExpr Bool * RtlExpr (fst (snd meth))) (RtlExpr (fst (snd meth))) :=
    match order with
    | o :: order' => let wc' := getMethEnsOrder order' in
                     match getRule m o with
                     | Some r =>
                       let wm' := getMethEns (fst r) meth (snd r _) (1 :: nil) in
                       match wc', wm' with
                       | inr x, inr y => inr x
                       | inl wc'', inr y => inl wc''
                       | inr x, inl wm'' => inl wm''
                       | inl wc'', inl wm'' =>
                         inl (conditionPair (fst wc'') wc'' wm'')%rtl_expr
                       end
                       (* (RtlITE (wc' @% "valid") wc' *)
                       (*         match getMethEns (fst r) meth (snd r _) (1 :: nil) with *)
                       (*         | Some methEns => methEns *)
                       (*         | None => invalidRtl _ *)
                       (*         end *)
                       (* )%rtl_expr *)
                     | None => match getMeth m o with
                               | Some r =>
                                 let wm' := getMethEns (fst r) meth (projT2 (snd r) _ (1 :: nil)) (2 :: nil) in
                                 match wc', wm' with
                                 | inr y, inr z => inr y
                                 | inl wc'', inr z => inl wc''
                                 | inr y, inl wm'' => inl wm''
                                 | inl wc'', inl wm'' =>
                                   inl (conditionPair (fst wc'') wc'' wm'')%rtl_expr
                                 end
                               | None => inr (RtlConst (getDefaultConst _))
                               end
                     end
    | nil => (* invalidRtl _ *) inr (RtlConst (getDefaultConst _))
    end.

  Definition getMethEnsOrderEn order :=
    match getMethEnsOrder order with
    | inr x => (getMethEn (fst meth), existT _ Bool (RtlConst false))%rtl_expr
    | inl vals => (getMethEn (fst meth), existT _ Bool (fst vals))%rtl_expr
    end.
    (* (getMethEn (fst meth), existT _ Bool (getMethEnsRules rules @% "valid"))%rtl_expr. *)

  Definition getMethEnsOrderArg order :=
    match getMethEnsOrder order with
    | inr x => (getMethArg (fst meth), existT _ _ x)%rtl_expr
    | inl vals => (getMethArg (fst meth), existT _ _ (snd vals))%rtl_expr
    end.
    (* (getMethArg (fst meth), existT _ _ (getMethEnsRules rules @% "data"))%rtl_expr. *)
  Close Scope string.
End ForMeth.


Definition getMethEnsOrderFull m order := map (fun meth => getMethEnsOrderEn m meth order) (getCallsWithSignPerMod (Base m)) ++
                                              map (fun meth => getMethEnsOrderArg m meth order) (getCallsWithSignPerMod (Base m)).

Definition getSysPerRule (rule: Attribute (Action Void)) :=
  getRtlSys (fst rule) (snd rule (fun _ => list nat)) (RtlReadWire Bool (getActionGuard (fst rule))) (1 :: nil).

Definition getSysPerMeth (meth: DefMethT) :=
  getRtlSys (fst meth) (projT2 (snd meth) (fun _ => list nat) (1 :: nil)) (RtlReadWire Bool (getActionGuard (fst meth))) (2 :: nil).

Definition getSysPerBaseMod m := concat (map getSysPerRule (getRules m) ++ map getSysPerMeth (getMethods m)).

(* Set the enables correctly in the following two functions *)

Definition computeRuleAssigns (r: Attribute (Action Void)) :=
  (getActionGuard (fst r),
   existT _ Bool (convertActionToRtl_guardF (fst r) (snd r (fun _ => list nat)) (1 :: nil)))
    ::
    (getActionEn (fst r), existT _ Bool (RtlReadWire Bool (getActionGuard (fst r))))
    ::
    convertActionToRtl_noGuard (fst r) (snd r (fun _ => list nat)) (1 :: nil) (0 :: nil).

Definition computeRuleAssignsRegs regs (r: Attribute (Action Void)) :=
  convertRegsWrites (fst r) regs (snd r (fun _ => list nat)) (1 :: nil).

Definition computeMethAssigns (f: DefMethT) :=
  (getMethGuard (fst f),
   existT _ Bool (convertActionToRtl_guardF (fst f) (projT2 (snd f) (fun _ => list nat) (1 :: nil)) (2 :: nil)))
    :: (fst f, (1 :: nil),
        existT _ (fst (projT1 (snd f))) (RtlReadWire _ (getMethArg (fst f))))
    :: (getMethRet (fst f),
        existT _ (snd (projT1 (snd f))) (RtlReadWire _ (fst f, (0 :: nil))))
    ::
    convertActionToRtl_noGuard (fst f) (projT2 (snd f) (fun _ => list nat) (1 :: nil)) (2 :: nil) (0 :: nil).

Definition computeMethAssignsRegs regs (f: DefMethT) :=
  convertRegsWrites (fst f) regs (projT2 (snd f) (fun _ => list nat) (1 :: nil)) (2 :: nil).

Definition getInputs (calls defs: list (Attribute (Kind * Kind))) := map (fun x => (getMethRet (fst x), snd (snd x))) calls ++
                                                                         map (fun x => (getMethArg (fst x), fst (snd x))) defs ++
                                                                         map (fun x => (getMethEn (fst x), Bool)) defs.

Definition getInputGuards (calls: list (Attribute (Kind * Kind))) := map (fun x => (getMethGuard (fst x), Bool)) calls.

Definition getOutputs (calls defs: list (Attribute (Kind * Kind))) := map (fun x => (getMethArg (fst x), fst (snd x))) calls ++
                                                                          map (fun x => (getMethEn (fst x), Bool)) calls ++
                                                                          map (fun x => (getMethRet (fst x), snd (snd x))) defs ++
                                                                          map (fun x => (getMethGuard (fst x), Bool)) defs.

Definition getRegInit (y: sigT RegInitValT): {x: Kind & option (ConstT x)} :=
  existT _ _
         match projT2 y with
         | Uninit => None
         | Init y' => Some match y' in ConstFullT k return ConstT match k with
                                                                  | SyntaxKind k' => k'
                                                                  | _ => Void
                                                                  end with
                           | SyntaxConst k c => c
                           | _ => WO
                           end
         | RegFileUninit num k pf => None
         | RegFileInit num k pf val =>
           Some
             match eq_sym pf in _ = Y return ConstT match Y with
                                                    | SyntaxKind k' => k'
                                                    | NativeKind _ => Void
                                                    end with
             | eq_refl => ConstArray (fun _ => val)
             end
             
         | RegFileHex num k pf file => None
         | RegFileBin num k pf file => None
         end.

Fixpoint getAllWriteReadConnections' (regs: list RegInitT) (order: list string) :=
  match order with
  | penult :: xs =>
    match xs with
    | ult :: ys =>
      map (fun r => (getRegActionRead ult (fst r), existT _ _ (RtlReadWire (projT1 (getRegInit (snd r))) (getRegActionFinalWrite penult (fst r))))) regs
          ++ getAllWriteReadConnections' regs xs
    | nil =>
      map (fun r => (getRegWrite (fst r), existT _ _ (RtlReadWire (projT1 (getRegInit (snd r))) (getRegActionFinalWrite penult (fst r))))) regs
    end
  | nil => nil
  end.

Definition getAllWriteReadConnections (regs: list RegInitT) (order: list string) :=
  match order with
  | beg :: xs =>
    map (fun r => (getRegActionRead beg (fst r), existT _ _ (RtlReadWire (projT1 (getRegInit (snd r))) (getRegRead (fst r))))) regs
        ++ getAllWriteReadConnections' regs order
  | nil => nil
  end.

Definition getWires m (order: list string) :=
  concat (map computeRuleAssigns (getRules m)) ++ concat (map (computeRuleAssignsRegs (getRegisters m)) (getRules m)) ++
         concat (map computeMethAssigns (getMethods m)) ++ concat (map (computeMethAssignsRegs (getRegisters m)) (getMethods m)) ++
         getAllWriteReadConnections (getRegisters m) order ++
         getMethEnsOrderFull m order.
      
Definition getWriteRegs (regs: list RegInitT) :=
  map (fun r => (fst r, existT _ (projT1 (getRegInit (snd r))) (RtlReadWire _ (getRegWrite (fst r))))) regs.

Definition getReadRegs (regs: list RegInitT) :=
  map (fun r => (getRegRead (fst r), existT _ (projT1 (getRegInit (snd r))) (RtlReadReg _ (fst r)))) regs.

Definition filterNotInList A (f: A -> string) ls x :=
  if In_dec string_dec (f x) ls then false else true.

Definition getAllMethodsRegFileList ls :=
  concat (map (fun x => getMethods (BaseRegFile x)) ls).

Definition SubtractList A B (f: A -> string) (g: B -> string) l1 l2 :=
  filter (filterNotInList f (map g l2)) l1.

Definition setMethodGuards (ignoreMeths: list string) m :=
  map (fun m => (getMethGuard (fst m), existT _ Bool (RtlConst (ConstBool true)))) (SubtractList fst id (getCallsWithSignPerMod (Base m)) ignoreMeths).

(* Inputs and outputs must be all method calls in base module - register file methods being called *)
(* Reg File methods definitions must serve as wires *)
Definition getRtl_full (bm: (list string * (list RegFileBase * BaseModule))) (preserveGuards: list string) (order: list string) :=
  {| hiddenWires := map (fun x => getMethRet x) (fst bm) ++ map (fun x => getMethArg x) (fst bm) ++ map (fun x => getMethEn x) (fst bm);
     regFiles := map (fun x => (false, x)) (fst (snd bm));
     inputs := getInputs (SubtractList fst fst (getCallsWithSignPerMod (Base (snd (snd bm))))
                                       (getAllMethodsRegFileList (fst (snd bm))))
                         (SubtractList fst fst (map (fun x => (fst x, projT1 (snd x))) (getMethods (snd (snd bm))))
                                       (getAllMethodsRegFileList (fst (snd bm))))
                         ++
                         getInputGuards (filter (fun x => getBool (in_dec string_dec (fst x) preserveGuards))
                                                (getCallsWithSignPerMod (Base (snd (snd bm)))));
     outputs := getOutputs (SubtractList fst fst (getCallsWithSignPerMod (Base (snd (snd bm))))
                                         (getAllMethodsRegFileList (fst (snd bm))))
                           (SubtractList fst fst (map (fun x => (fst x, projT1 (snd x))) (getMethods (snd (snd bm))))
                                         (getAllMethodsRegFileList (fst (snd bm))));
     regInits := map (fun x => (fst x, getRtlRegInit (snd x))) (getRegisters (snd (snd bm)));
     regWrites := getWriteRegs (getRegisters (snd (snd bm)));
     wires := getReadRegs (getRegisters (snd (snd bm))) ++ getWires (snd (snd bm)) order ++
                          setMethodGuards (map fst (getAllMethodsRegFileList (fst (snd bm))) ++ preserveGuards) (snd (snd bm));
     sys := getSysPerBaseMod (snd (snd bm)) |}.

Definition getRtl (bm: (list string * (list RegFileBase * BaseModule))) := getRtl_full bm nil (map fst (getRules (snd (snd bm)))).

Definition rtlGet m pgs :=
  getRtl_full (getHidden m, (fst (separateBaseMod m), inlineAll_All_mod (mergeSeparatedBaseMod (snd (separateBaseMod m))))) pgs (map fst (getAllRules m)).

Definition makeRtl (m: ModWfOrd) pgs :=
  getRtl_full (getHidden m, (fst (separateBaseMod m), inlineAll_All_mod (mergeSeparatedBaseMod (snd (separateBaseMod m))))) pgs (modOrd m).
*)