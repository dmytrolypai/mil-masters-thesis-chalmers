-- | Type/lint checker helpers tests.
module MIL.TypeChecker.HelpersSpec (main, spec) where

import Test.Hspec
import Control.Applicative
import qualified Data.Set as Set

import MIL.AST
import MIL.AST.Builder
import MIL.BuiltIn
import MIL.TypeChecker.Helpers
import MIL.TypeChecker.TypeCheckM
import MIL.TypeChecker.TypeEnv
import MIL.TypeChecker.TcError

-- | To be able to run this module from GHCi.
main :: IO ()
main = hspec spec

-- | Main specification function.
spec :: Spec
spec = do
  describe "checkType" $ do
    it "checks a built-in type" $
      let t = unitType
      in successCase t

    it "checks a type constructor" $
      let t = TyTypeCon (TypeName "T")
      in successCaseWithSetup (addTypeM (TypeName "T") StarK) t

    it "gives an error when type constructor is undefined" $
      let t = TyTypeCon (TypeName "T")
          tcError = TypeNotDefined (TypeName "T")
      in failureCase t tcError

    it "gives an error when type variable is not in scope" $
      let t = TyVar $ TypeVar "A"
          tcError = TypeVarNotInScope $ TypeVar "A"
      in failureCase t tcError

    it "checks a function type (with built-in types)" $
      let t = TyArrow boolType intType
      in successCase t

    it "checks a forall type (simple type var)" $
      let t = TyForAll (TypeVar "A") (mkTypeVar "A")
      in successCase t

    it "checks a nested forall type" $
      let t = TyForAll (TypeVar "A")
                (TyForAll (TypeVar "B")
                   (TyArrow (mkTypeVar "A") (mkTypeVar "B")))
      in successCase t

    it "doesn't allow a type variable in forall to shadow a type" $
      let t = TyForAll (TypeVar "T") (mkTypeVar "T")
          tcError = TypeVarShadowsType (TypeVar "T")
      in failureCaseWithSetup (addTypeM (TypeName "T") StarK) t tcError

    it "doesn't allow a type variable in forall to shadow another type variable" $
      let t = TyForAll (TypeVar "A") (TyForAll (TypeVar "A") unitType)
          tcError = TypeVarShadowsTypeVar (TypeVar "A")
      in failureCase t tcError

    it "checks forall types with the same type variable name on different sides of function arrow" $
      let t = TyArrow (TyForAll (TypeVar "A") (mkTypeVar "A"))
                      (TyForAll (TypeVar "A") (mkTypeVar "A"))
      in successCase t

    it "checks type application" $
      let t = TyApp (TyApp (mkSimpleType "Pair") unitType) boolType
      in successCaseWithSetup (addTypeM (TypeName "Pair") (mkKind 2)) t

    it "doesn't allow function type to be the left component of type application" $
      let t = TyApp (TyArrow unitType unitType) boolType
          tcError = IllFormedType t
      in failureCase t tcError

    it "doesn't allow tuple type to be the left component of type application" $
      let t = TyApp (TyTuple [unitType, unitType]) boolType
          tcError = IllFormedType t
      in failureCase t tcError

    it "performs a kind checking (too many arguments)" $
      let t = TyApp (TyApp (TyApp (mkSimpleType "Pair")
                                  unitType)
                           boolType)
                    intType
          tcError = TypeConIncorrectApp (TypeName "Pair") (mkKind 2) (mkKind 3)
      in failureCaseWithSetup (addTypeM (TypeName "Pair") (mkKind 2)) t tcError

    it "performs a kind checking (too few arguments)" $
      let t = TyApp (mkSimpleType "Pair") unitType
          tcError = TypeConIncorrectApp (TypeName "Pair") (mkKind 2) (mkKind 1)
      in failureCaseWithSetup (addTypeM (TypeName "Pair") (mkKind 2)) t tcError

    it "only allows types of kind '*' as components of function arrow" $
      let t = TyArrow (mkSimpleType "T") unitType
          tcError = TypeConIncorrectApp (TypeName "T") (mkKind 1) StarK
      in failureCaseWithSetup (addTypeM (TypeName "T") (mkKind 1)) t tcError

    it "only allows type variables of kind '*'" $
      let t = TyForAll (TypeVar "A") (TyApp (mkTypeVar "A") unitType)
          tcError = TypeVarApp (TypeVar "A")
      in failureCase t tcError

    it "checks a tuple type (with built-in types)" $
      let t = TyTuple [floatType, charType]
      in successCase t

    it "only allows types of kind '*' as tuple elements" $
      let t = TyTuple [unitType, mkSimpleType "T"]
          tcError = TypeConIncorrectApp (TypeName "T") (mkKind 1) StarK
      in failureCaseWithSetup (addTypeM (TypeName "T") (mkKind 1)) t tcError

    it "checks a type application with single built-in monad" $
      let t = TyApp (TyMonad (MTyMonad $ SinMonad IO)) unitType
      in successCase t

    it "checks a type application with parameterised built-in monad" $
      let t = TyApp (TyMonad (MTyMonad $ SinMonadApp (SinMonad Error) unitType)) intType
      in successCase t

    it "checks a type application with monad cons" $
      let t = TyApp (TyMonad $ MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad IO)) intType
      in successCase t

    it "checks a type application with monad cons (with parameterised monad)" $
      let t = TyApp (TyMonad $ MTyMonadCons (SinMonadApp (SinMonad Error) unitType) (MTyMonad $ SinMonad State)) unitType
      in successCase t

    it "performs a kind checking on built-in monads" $
      let t = TyMonad $ MTyMonad (SinMonad Id)
          tcError = TypeIncorrectKind t (mkKind 1) StarK
      in failureCase t tcError

    it "performs a kind checking on built-in monads (parameterised monad)" $
      let t = TyApp (TyMonad $ MTyMonad (SinMonad Error)) unitType
          tcError = TypeConIncorrectApp (TypeName "Error") (mkKind 2) (mkKind 1)
      in failureCase t tcError

    it "performs a kind checking on built-in monads (in monad cons)" $
      let t = TyApp (TyMonad $ MTyMonadCons (SinMonad Error) (MTyMonad $ SinMonad State))
                    boolType
          tcError = TypeConIncorrectApp (TypeName "Error") (mkKind 2) (mkKind 1)
      in failureCase t tcError

    it "checks a nested monad cons" $
      let t = TyApp (TyMonad $ MTyMonadCons (SinMonad IO)
                                 (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id)))
                    unitType
      in successCase t

  describe "checkTypeWithTypeVars" $ do
    it "checks a type variable" $
      let t = mkTypeVar "A" in
      fst <$> runTypeCheckM (checkTypeWithTypeVars (Set.fromList [TypeVar "A"]) t) (initTypeEnv $ repeat defaultMonadError)
        `shouldBe` Right ()

  describe "checkTypeWithTypeVarsOfKind" $ do
    it "performs kind checking for function type" $
      let t = TyArrow unitType boolType
          tcError = TypeIncorrectKind t StarK (mkKind 1) in
      fst <$> runTypeCheckM (checkTypeWithTypeVarsOfKind Set.empty (mkKind 1) t) (initTypeEnv $ repeat defaultMonadError)
        `shouldBe` Left tcError

    it "performs kind checking for forall type" $
      let t = TyForAll (TypeVar "A") (TyMonad $ MTyMonad (SinMonad Id)) in
      fst <$> runTypeCheckM (checkTypeWithTypeVarsOfKind Set.empty (mkKind 1) t) (initTypeEnv $ repeat defaultMonadError)
        `shouldBe` Right ()

    it "performs kind checking for tuple type" $
      let t = TyTuple [unitType]
          tcError = TypeIncorrectKind t StarK (mkKind 1) in
      fst <$> runTypeCheckM (checkTypeWithTypeVarsOfKind Set.empty (mkKind 1) t) (initTypeEnv $ repeat defaultMonadError)
        `shouldBe` Left tcError

  describe "isMonadSuffixOf" $ do
    it "is reflexive" $
      let m = MTyMonad (SinMonad Id)
      in m `isMonadSuffixOf` m

    it "returns False for two different monads" $
      let m1 = MTyMonad (SinMonad Id)
          m2 = MTyMonad (SinMonad State)
      in not $ m1 `isMonadSuffixOf` m2

    it "handles alpha equivalence" $
      let m1 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "A") (mkTypeVar "A")))
          m2 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "B") (mkTypeVar "B")))
      in m1 `isMonadSuffixOf` m2

    it "is not commutative" $
      let m1 = MTyMonad (SinMonad Id)
          m2 = MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id)
      in (m1 `isMonadSuffixOf` m2) `shouldBe` not (m2 `isMonadSuffixOf` m1)

    it "handles two monad conses" $
      let m1 = MTyMonadCons (SinMonad Id) (MTyMonad $ SinMonad IO)
          m2 = MTyMonadCons (SinMonad State) m1
      in m1 `isMonadSuffixOf` m2

    it "returns False for non-matching ending" $
      let m1 = MTyMonadCons (SinMonad Id) (MTyMonad $ SinMonad IO)
          m2 = MTyMonadCons (SinMonad State) (MTyMonadCons (SinMonad Id) (MTyMonad $ SinMonad Id))
      in not $ m1 `isMonadSuffixOf` m2

    it "returns False for a suffix with injected monad (bug)" $
      let m1 = MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad Id)
          m2 = MTyMonadCons (SinMonad IO) (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id))
      in not $ m1 `isMonadSuffixOf` m2

  describe "isCompatibleMonadWith" $ do
    it "is reflexive" $
      let m = MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad Id)
      in m `isCompatibleMonadWith` m

    it "returns False for incompatible monads" $
      let m1 = MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad Id)
          m2 = MTyMonadCons (SinMonad IO) (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id))
      in not $ m1 `isCompatibleMonadWith` m2

    it "handles alpha equivalence" $
      let m1 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "A") (mkTypeVar "A")))
          m2 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "B") (mkTypeVar "B")))
      in m1 `isCompatibleMonadWith` m2

    it "is commutative" $
      let m1 = MTyMonadCons (SinMonad IO) (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id))
          m2 = MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)
      in (m1 `isCompatibleMonadWith` m2) `shouldBe` (m2 `isCompatibleMonadWith` m1)

  describe "isCompatibleWith" $ do
    it "is reflexive" $
      let t = TyApp (TyMonad $ MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad IO)) intType
      in t `isCompatibleWith` t

    it "returns True for compatible types" $
      let t1 = TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)
          t2 = TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id))
      in t1 `isCompatibleWith` t2

    it "returns False for incompatible types" $
      let t1 = unitType
          t2 = boolType
      in not $ t1 `isCompatibleWith` t2

    it "returns False for incompatible monadic types" $  -- TODO: future work, commutative effects?
      let t1 = TyMonad $ MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad IO)
          t2 = TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)
      in not $ t1 `isCompatibleWith` t2

    it "handles alpha equivalence" $
      let t1 = TyApp (TyMonad $ MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "A") (mkTypeVar "A")))) intType
          t2 = TyApp (TyMonad $ MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "B") (mkTypeVar "B")))) intType
      in t1 `isCompatibleWith` t2

    it "is not commutative" $
      let t1 = TyApp (TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)) boolType
          t2 = TyApp (TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad Id))) boolType
      in (t1 `isCompatibleWith` t2) `shouldBe` not (t2 `isCompatibleWith` t1)

    it "is covariant in the monad application result type (when it is not a monad itself)" $
      let t1 = TyApp (TyMonad $ MTyMonad (SinMonad IO)) (TyTuple [boolType, unitType])
          t2 = TyApp (TyMonad $ MTyMonad (SinMonad IO)) (TyTuple [boolType])
      in t1 `isCompatibleWith` t2

    it "is covariant in the return type and contravariant in the argument type for function types" $
      let t1 = TyArrow (TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)) (TyMonad $ MTyMonad (SinMonad IO))
          t2 = TyArrow (TyMonad $ MTyMonad (SinMonad IO)) (TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State))
      in t1 `isCompatibleWith` t2

    it "considers a type under forall type" $
      let t1 = TyForAll (TypeVar "A") (TyMonad $ MTyMonad (SinMonad IO))
          t2 = TyForAll (TypeVar "B") (TyMonad $ MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State))
      in t1 `isCompatibleWith` t2

  describe "isSubTypeOf" $ do
    it "is reflexive" $
      let t = TyTuple [boolType, intType]
      in t `isSubTypeOf` t

    it "is not commutative for tuples" $
      let t1 = TyTuple [intType]
          t2 = TyTuple [intType, boolType]
      in (t1 `isSubTypeOf` t2) `shouldBe` not (t2 `isSubTypeOf` t1)

    it "supports width subtyping for tuples" $
      let t1 = TyTuple [intType, boolType]
          t2 = TyTuple [intType]
      in t1 `isSubTypeOf` t2

    it "supports depth subtyping for tuples" $
      let t1 = TyTuple [TyTuple [intType, boolType], boolType]
          t2 = TyTuple [TyTuple [intType]]
      in t1 `isSubTypeOf` t2

    it "is alpha equivalence for types other than tuples" $
      let t1 = TyForAll (TypeVar "A") (TyVar $ TypeVar "A")
          t2 = TyForAll (TypeVar "B") (TyVar $ TypeVar "B")
      in t1 `isSubTypeOf` t2

  describe "highestEffectMonadType" $ do
    it "returns the one which has more effects in the stack (both cons)" $
      let mt1 = MTyMonadCons (SinMonad Id) (MTyMonad $ SinMonad IO)
          mt2 = MTyMonadCons (SinMonad Id) (MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State))
      in highestEffectMonadType mt1 mt2 `shouldBe` mt2

    it "returns the one which has more effects in the stack (one without cons)" $
      let mt1 = MTyMonad (SinMonad IO)
          mt2 = MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State)
      in highestEffectMonadType mt1 mt2 `shouldBe` mt2

    it "returns the first one if monad types are alpha-equivalent (both cons)" $
      let mt1 = MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad IO)
          mt2 = MTyMonadCons (SinMonad State) (MTyMonad $ SinMonad IO)
      in highestEffectMonadType mt1 mt2 `shouldBe` mt1

    it "returns the first one if monad types are alpha-equivalent (both without cons)" $
      let mt1 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "A") (mkTypeVar "A")))
          mt2 = MTyMonad (SinMonadApp (SinMonad Error) (TyForAll (TypeVar "B") (mkTypeVar "B")))
      in highestEffectMonadType mt1 mt2 `shouldBe` mt1

    it "is commutative" $
      let mt1 = MTyMonadCons (SinMonad Id) (MTyMonad $ SinMonad IO)
          mt2 = MTyMonadCons (SinMonad Id) (MTyMonadCons (SinMonad IO) (MTyMonad $ SinMonad State))
      in highestEffectMonadType mt1 mt2 `shouldBe` highestEffectMonadType mt2 mt1

-- * Infrastructure

successCase :: Type -> IO ()
successCase = successCaseWithSetup (return ())

successCaseWithSetup :: TypeCheckM () -> Type -> IO ()
successCaseWithSetup setup t =
  fst <$> runTypeCheckM (setup >> checkType t) (initTypeEnv $ repeat defaultMonadError)
    `shouldBe` Right ()

failureCase :: Type -> TcError -> IO ()
failureCase = failureCaseWithSetup (return ())

failureCaseWithSetup :: TypeCheckM () -> Type -> TcError -> IO ()
failureCaseWithSetup setup t tcError =
  fst <$> runTypeCheckM (setup >> checkType t) (initTypeEnv $ repeat defaultMonadError)
    `shouldBe` Left tcError

