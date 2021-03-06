-- | Functions for working with types. Used in the type/lint checker.
module MIL.TypeChecker.Helpers where

import qualified Data.Set as Set
import Data.List (foldl')

import MIL.AST
import MIL.AST.Builder
import MIL.AST.Helpers
import MIL.TypeChecker.TypeCheckM
import MIL.TypeChecker.TcError
import MIL.TypeChecker.AlphaEq
import MIL.TypeChecker.TypeSubstitution
import MIL.BuiltIn
import MIL.Utils

-- | Checks if the type is well-formed, well-kinded and uses types in scope.
--
-- For details see 'checkTypeWithTypeVars'.
checkType :: Type -> TypeCheckM ()
checkType = checkTypeWithTypeVars Set.empty

-- | Checks if the type is well-formed, well-kinded and uses types in scope.
--
-- Takes a set of type variables which are already in scope (used for type
-- parameters in data type definitions and forall types).
--
-- For details see 'checkTypeWithTypeVarsOfKind'.
checkTypeWithTypeVars :: Set.Set TypeVar -> Type -> TypeCheckM ()
checkTypeWithTypeVars typeVars = checkTypeWithTypeVarsOfKind typeVars StarK

-- | Checks if the type is well-formed, uses types in scope, has a given kind and
-- that all nested types are well-kinded.
--
-- Takes a set of type variables which are already in scope (used for type
-- parameters in data type definitions and forall types).
--
-- For details see inline comments.
checkTypeWithTypeVarsOfKind :: Set.Set TypeVar -> Kind -> Type -> TypeCheckM ()
checkTypeWithTypeVarsOfKind typeVars kind t =
  case t of
    TyTypeCon typeName ->
      ifM (isTypeDefinedM typeName)
        (do dataTypeKind <- getDataTypeKindM typeName
            when (dataTypeKind /= kind) $
              throwError $ TypeConIncorrectApp typeName dataTypeKind kind)
        (throwError $ TypeNotDefined typeName)

    TyVar typeVar -> do
      isTyVarBound <- isTypeVarBoundM typeVar
      -- It is important to check in both places, since typeVars is not queried
      -- by 'isTypeVarBoundM'.
      unless (isTyVarBound || typeVar `Set.member` typeVars) $
        throwError $ TypeVarNotInScope typeVar

    TyArrow t1 t2 -> do
      unless (kind == StarK) $
        throwError $ TypeIncorrectKind t StarK kind
      checkTypeWithTypeVars typeVars t1
      checkTypeWithTypeVars typeVars t2

    TyForAll typeVar bodyT -> do
      -- It is important to check in all these places, since it can shadow a
      -- type or another type variable and typeVars is not queried by
      -- 'isTypeDefinedM' and 'isTypeVarBoundM'.
      whenM (isTypeDefinedM $ typeVarToTypeName typeVar) $
        throwError $ TypeVarShadowsType typeVar
      isTyVarBound <- isTypeVarBoundM typeVar
      when (isTyVarBound || typeVar `Set.member` typeVars) $
        throwError $ TypeVarShadowsTypeVar typeVar
      -- forall type extends a set of type variables which are in scope
      let typeVars' = Set.insert typeVar typeVars
      checkTypeWithTypeVarsOfKind typeVars' kind bodyT

    TyApp t1 t2 ->
      case t1 of
        TyTypeCon {} -> do
          -- Type constructor is on the left-hand side of the application, it
          -- should have extra * in the kind (on the left) in order for the
          -- type to be well-kinded.
          checkTypeWithTypeVarsOfKind typeVars (StarK :=>: kind) t1

          -- Start from kind *, it is another type constructor (another
          -- application).
          checkTypeWithTypeVars typeVars t2

        TyApp {} -> do
          -- One more application on the left, add * to the kind.
          checkTypeWithTypeVarsOfKind typeVars (StarK :=>: kind) t1

          -- Start from kind *, it is another type constructor (another
          -- application).
          checkTypeWithTypeVars typeVars t2

        TyMonad mt ->
          -- Monad is on the left-hand side of the application, it
          -- should have extra * in the kind (on the left) in order for
          -- the type to be well-kinded
          checkMonadTypeWithTypeVarsOfKind typeVars (StarK :=>: kind) mt

        -- Type variables are always of kind *, so they cannot be applied
        TyVar tv -> throwError $ TypeVarApp tv

        -- Nothing else can be applied
        _ -> throwError $ IllFormedType t

    TyTuple elemTypes -> do
      unless (kind == StarK) $
        throwError $ TypeIncorrectKind t StarK kind
      mapM_ (checkTypeWithTypeVars typeVars) elemTypes

    TyMonad mt -> checkMonadTypeWithTypeVarsOfKind typeVars kind mt

-- | Checks if the monadic type is well-formed, uses types in scope, has a kind
-- * => * and that all nested types are well-kinded.
--
-- For details see 'checkMonadTypeWithTypeVarsOfKind'.
checkMonadType :: MonadType -> TypeCheckM ()
checkMonadType = checkMonadTypeWithTypeVarsOfKind Set.empty (mkKind 1)

-- | Checks if the monadic type is well-formed, uses types in scope, has a
-- given kind and that all nested types are well-kinded.
--
--
-- Takes a set of type variables which are already in scope (used for type
-- parameters in data type definitions and forall types).
checkMonadTypeWithTypeVarsOfKind :: Set.Set TypeVar -> Kind -> MonadType -> TypeCheckM ()
checkMonadTypeWithTypeVarsOfKind typeVars kind mt = do
  -- Monadic types have kind * -> *
  unless (kind == mkKind 1) $
    throwError $ TypeIncorrectKind (TyMonad mt) (mkKind 1) kind
  case mt of
    MTyMonad sm -> checkSingleMonadWithTypeVarsOfKind typeVars (mkKind 1) sm
    MTyMonadCons sm mt' -> do
      checkSingleMonadWithTypeVarsOfKind typeVars (mkKind 1) sm
      checkMonadTypeWithTypeVarsOfKind typeVars (mkKind 1) mt'

-- | Checks if a single monad is well-formed, uses types in scope, has a given
-- kind and that all nested types are well-kinded.
--
-- Takes a set of type variables which are already in scope (used for type
-- parameters in data type definitions and forall types).
--
-- For details see inline comments.
checkSingleMonadWithTypeVarsOfKind :: Set.Set TypeVar -> Kind -> SingleMonad -> TypeCheckM ()
checkSingleMonadWithTypeVarsOfKind typeVars kind sm =
  case sm of
    SinMonad m ->
      let monadTypeName = builtInMonadTypeName m
          monadKind = getBuiltInMonadKind monadTypeName in
      unless (monadKind == kind) $
        throwError $ TypeConIncorrectApp monadTypeName monadKind kind
    SinMonadApp sm' t -> do
      -- One more application on the left, add * to the kind.
      checkSingleMonadWithTypeVarsOfKind typeVars (StarK :=>: kind) sm'

      -- Start from kind *, it is another type constructor (another
      -- application)
      checkTypeWithTypeVars typeVars t

-- * Type construction

-- | Constructs an arrow type given a result type and a list of parameter
-- types.
tyArrowFromList :: Type -> [Type] -> Type
tyArrowFromList = foldr TyArrow

-- | Constructs a type application given a type name and a list of type variables.
tyAppFromList :: TypeName -> [TypeVar] -> Type
tyAppFromList typeName = foldl' (\acc tv -> TyApp acc (TyVar tv)) (TyTypeCon typeName)

-- | Constructs a forall type given a body type and a list of type variables.
tyForAllFromList :: Type -> [TypeVar] -> Type
tyForAllFromList = foldr TyForAll

-- | Takes a scrutinee type and a type of the data constructor (for error
-- message) and transforms a series of type applications and eventual type
-- constructor to a pair of type constructor name and a list of its type
-- arguments. If it encounters other types, it throws an error. Used when
-- checking data constructor pattern.
transformScrutType :: Type -> Type -> TypeCheckM (TypeName, [Type])
transformScrutType scrutType conType = transformScrutType' scrutType []
  where transformScrutType' :: Type -> [Type] -> TypeCheckM (TypeName, [Type])
        transformScrutType' scrutT typeArgs =
          case scrutT of
            TyTypeCon typeName -> return (typeName, typeArgs)
            TyApp t1 t2 -> transformScrutType' t1 (t2:typeArgs)
            -- If the scrutinee has a type other than a type application, then this
            -- pattern can not be type correct. Data constructors have a
            -- monomorphic fully applied type constructor type.
            _ -> throwError $ PatternIncorrectType scrutType conType

-- | Given a data constructor function type, recovers its field types.
-- Takes a list of type arguments to the type constructor (which is fully
-- applied). It is used for substitution when coming across forall types.
conFieldTypesFromType :: Type -> [Type] -> [Type]
conFieldTypesFromType t typeArgs = init $ conFieldTypesFromType' t typeArgs
  where conFieldTypesFromType' (TyForAll typeVar forallBodyType) (tyArg:tyArgs) =
          conFieldTypesFromType' ((typeVar, tyArg) `substTypeIn` forallBodyType) tyArgs
        conFieldTypesFromType' (TyArrow t1 t2)  [] =
          conFieldTypesFromType' t1 [] ++ conFieldTypesFromType' t2 []
        conFieldTypesFromType' tyCon@(TyTypeCon {}) [] = [tyCon]
        conFieldTypesFromType' tyApp@(TyApp {}) [] = [tyApp]
        conFieldTypesFromType' tyVar@(TyVar {}) [] = [tyVar]
        conFieldTypesFromType' tyTuple@(TyTuple {}) [] = [tyTuple]
        conFieldTypesFromType'          _ _ = error "conFieldTypesFromType: kind checking must have gone wrong"

-- * Helpers for monadic types

-- | Checks if two types are compatible. For most types this simply means alpha
-- equivalence. For some types it means subtyping. For monadic types this means
-- non-commutative monad compatibility (mt1 is a prefix of mt2). (see
-- 'isCompatibleMonadWith').
--
-- This operation is reflexive.
-- This operation is *not* commutative.
isCompatibleWith :: Type -> Type -> Bool
isCompatibleWith (TyMonad mt1) (TyMonad mt2) =
  mt1 `isCompatibleMonadWithNotCommut` mt2
isCompatibleWith (TyApp mt1@(TyMonad _) t1@(TyMonad {})) (TyApp mt2@(TyMonad _) t2@(TyMonad {})) =
  error "isCompatibleWith: monad is applied to a monad. Kind checking must have gone wrong."
isCompatibleWith (TyApp mt1@(TyMonad _) t1) (TyApp mt2@(TyMonad _) t2) =
  (mt1 `isCompatibleWith` mt2) && (t1 `isCompatibleWith` t2)
isCompatibleWith (TyArrow t11 t12) (TyArrow t21 t22) =
  (t21 `isCompatibleWith` t11) && (t12 `isCompatibleWith` t22)
isCompatibleWith (TyForAll tv1 t1) (TyForAll tv2 t2) =
  t1 `isCompatibleWith` ((tv2, TyVar tv1) `substTypeIn` t2)
isCompatibleWith t1 t2 = t1 `isSubTypeOf` t2

-- | Subtyping relation.
-- For tuple types it is width and depth subtyping.
-- All other types just use alpha equivalence.
--
-- This operation is reflexive.
-- This operation is *not* commutative (for tuples).
isSubTypeOf :: Type -> Type -> Bool
isSubTypeOf (TyTuple elemTypes1) (TyTuple elemTypes2) =
  length elemTypes1 >= length elemTypes2 && and (zipWith isSubTypeOf elemTypes1 elemTypes2)
isSubTypeOf t1 t2 = t1 `alphaEq` t2

-- | Not commutative version of 'isCompatibleMonadWith'.
isCompatibleMonadWithNotCommut :: MonadType -> MonadType -> Bool
isCompatibleMonadWithNotCommut (MTyMonad m1) (MTyMonad m2) = m1 `alphaEq` m2
isCompatibleMonadWithNotCommut (MTyMonadCons m1 mt1) (MTyMonadCons m2 mt2) =
  (m1 `alphaEq` m2) && (mt1 `isCompatibleMonadWithNotCommut` mt2)
isCompatibleMonadWithNotCommut (MTyMonad m1) (MTyMonadCons m2 _) = m1 `alphaEq` m2
isCompatibleMonadWithNotCommut _ _ = False

-- | Checks if two monads are compatible. This means if one of them is alpha
-- equivalent to another or one of them is a prefix of another.
-- For example, m1 is a prefix of m1 ::: m2.
--
-- This operation is reflexive.
-- This operation is commutative.
isCompatibleMonadWith :: MonadType -> MonadType -> Bool
isCompatibleMonadWith mt1 mt2 =
  (mt1 `isCompatibleMonadWithNotCommut` mt2) || (mt2 `isCompatibleMonadWithNotCommut` mt1)

-- | Checks if the first monad is a suffix of the second one or if they are
-- alpha equivalent.
-- For example, m2 is a suffix of m1 ::: m2.
--
-- This operation is reflexive.
-- This operation is *not* commutative.
isMonadSuffixOf :: MonadType -> MonadType -> Bool
isMonadSuffixOf (MTyMonad m1) (MTyMonad m2) = m1 `alphaEq` m2
isMonadSuffixOf t1@(MTyMonadCons {}) t2@(MTyMonadCons _ mt2) =
  t1 `alphaEq` t2 || t1 `isMonadSuffixOf` mt2
isMonadSuffixOf t1@(MTyMonad {}) (MTyMonadCons _ mt2) = t1 `isMonadSuffixOf` mt2
isMonadSuffixOf (MTyMonadCons {}) (MTyMonad {}) = False

-- | Takes two monadic types and returns the one, which has highest effect
-- (most effects). Monad types must be compatible. See 'isCompatibleMonadWith'.
--
-- This operation is commutative.
highestEffectMonadType :: MonadType -> MonadType -> MonadType
highestEffectMonadType mt1@(MTyMonadCons {}) (MTyMonad {}) = mt1
highestEffectMonadType (MTyMonad {}) mt2@(MTyMonadCons {}) = mt2
highestEffectMonadType mt1@(MTyMonad {}) (MTyMonad {}) = mt1
highestEffectMonadType mt1@(MTyMonadCons _ mt1') mt2@(MTyMonadCons _ mt2') =
  if highestEffectMonadType mt1' mt2' == mt1'
    then mt1
    else mt2

