-- | Module containing common functions for Type and Lint checkers.
module MIL.TypeChecker.Common
  ( collectDefs
  , collectTypeDef
  , checkMain
  , checkShadowing
  ) where

import qualified Data.Set as Set

import MIL.AST
import MIL.TypeChecker.TypeCheckM
import MIL.TypeChecker.TcError
import MIL.Utils

-- | In order to be able to handle (mutually) recursive definitions, we need to
-- do an additional first pass to collect type names with their kinds, function
-- names and type signatures.
collectDefs ::
  [TypeDef t] -> (TypeDef t -> TypeCheckM ()) ->
  [FunDef v ct mt t] -> (FunDef v ct mt t -> TypeCheckM ()) ->
  TypeCheckM ()
collectDefs typeDefs collectTypeDefFun funDefs collectFunDefFun = do
  -- It is essential that we collect types and then functions,
  -- because function types may mention defined data types.
  mapM_ collectTypeDefFun typeDefs
  mapM_ collectFunDefFun funDefs

-- | Checks if the type is already defined.
-- Checks that all type variables are distinct.
-- Adds the type name and its kind to the type environment.
collectTypeDef :: TypeDef t -> TypeCheckM ()
collectTypeDef (TypeDef typeName typeVars _) = do
  whenM (isTypeDefinedM typeName) $
    throwError $ TypeAlreadyDefined typeName
  checkDistinctTypeVars typeVars
  let kind = mkKind (length typeVars)
  addTypeM typeName kind

-- | Checks that all type variables in a given list are distinct,
-- otherwise - throws an error.
checkDistinctTypeVars :: [TypeVar] -> TypeCheckM ()
checkDistinctTypeVars =
  foldM_ (\tvs tv ->
            if tv `Set.member` tvs
              then throwError $ TypeParamAlreadyDefined tv
              else return $ Set.insert tv tvs)
         Set.empty

-- | Program needs to have an entry point: `main`.
checkMain :: TypeCheckM ()
checkMain = do
  let mainFunName = FunName "main"
  unlessM (isFunctionDefinedM mainFunName) $
    throwError $ MainNotDefined mainFunName

-- | Checks that type variables in a given list do not shadow defined data
-- types.
checkShadowing :: [TypeVar] -> TypeCheckM ()
checkShadowing typeVars =
  forM_ typeVars (\tv ->
    whenM (isTypeDefinedM (typeVarToTypeName tv)) $
      throwError $ TypeParamShadowsType tv)

