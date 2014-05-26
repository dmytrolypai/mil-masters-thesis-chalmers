-- | Type checking module. Most of the functions follow the AST structure.
-- Built using the API from 'TypeCheckM'.
--
-- Source language compilers generate typed representation of MIL AST
-- (variables are annotated with their types). The main goal is to construct
-- the type environment and to ensure that the program generated by a source
-- language compiler is well-typed. Acts more as a linter. Helps to ensure that
-- transformations preserve typing.
module MIL.TypeChecker
  ( typeCheck
  , TypeEnv
  , TcError
  , prPrint
  ) where

import qualified Data.Set as Set
import Control.Applicative

import MIL.AST
import MIL.TypeChecker.TypeCheckM
import MIL.TypeChecker.TcError
import MIL.TypeChecker.Helpers
import MIL.BuiltIn
import MIL.Utils

-- | Main batch entry point to the TypeChecker.
-- In the case of success returns a typed program and a type environment.
typeCheck :: Program -> Either TcError TypeEnv
typeCheck program = runTypeCheckM (tcProgram program) initTypeEnv

-- | Entry point into the type checking of the program.
tcProgram :: Program -> TypeCheckM ()
tcProgram (Program (typeDefs, aliasDefs, funDefs)) = do
  collectDefs typeDefs aliasDefs funDefs
  -- Type parameters and function types have been checked.
  -- Now first information about definitions is in the environment:
  -- + type names and their kinds
  -- + type aliases
  -- + function names and their types
  checkMain
  mapM_ tcTypeDef typeDefs
  mapM_ tcFunDef funDefs

-- | In order to be able to handle (mutually) recursive definitions, we need to
-- do an additional first pass to collect type names with their kinds, type
-- aliases, function names and type signatures.
--
-- It collects:
--
-- * type names and their kinds
--
-- * type aliases
--
-- * function names and their types
--
-- It also does checking of type parameters and function types.
collectDefs :: [TypeDef] -> [AliasDef] -> [FunDef] -> TypeCheckM ()
collectDefs typeDefs aliasDefs funDefs = do
  -- It is essential that we collect types, then aliases and then functions,
  -- because function types may mention defined data types and type aliases.
  mapM_ collectTypeDef typeDefs
  mapM_ collectAliasDef aliasDefs
  mapM_ collectFunDef funDefs

-- | Checks if the type is already defined.
-- Checks that all type variables are distinct.
-- Adds the type name and its kind to the type environment.
collectTypeDef :: TypeDef -> TypeCheckM ()
collectTypeDef (TypeDef typeName typeVars _) = do
  whenM (isTypeDefined typeName) $
    throwError $ TypeAlreadyDefined typeName
  foldM_ (\tvs tv ->
            if tv `Set.member` tvs
              then throwError $ TypeParamAlreadyDefined tv
              else return $ Set.insert tv tvs)
         Set.empty typeVars
  let kind = mkKind (length typeVars)
  addType typeName kind

-- | Checks if the data type or another type alias with the same type name is
-- already defined.
-- Checks that the specified type is correct (well-formed, well-kinded and uses
-- types in scope).
-- Adds the type alias to the type environment.
-- Note: type aliases can *not* be recursive.
collectAliasDef :: AliasDef -> TypeCheckM ()
collectAliasDef (AliasDef typeName t) = do
  whenM (isTypeOrAliasDefined typeName) $
    throwError $ TypeOrAliasAlreadyDefined typeName
  checkType t
  addAlias typeName t

-- | Checks if the function is already defined.
-- Checks that the specified function type is correct (well-formed,
-- well-kinded and uses types in scope).
-- Adds the function and its type to the environment.
collectFunDef :: FunDef -> TypeCheckM ()
collectFunDef (FunDef funName funType _) = do
  whenM (isFunctionDefined funName) $
    throwError $ FunctionAlreadyDefined funName
  checkType funType
  addFunction funName funType

-- | Program needs to have an entry point: `main`.
checkMain :: TypeCheckM ()
checkMain = return ()  -- TODO

-- | Checks data constructors and adds them to the environment together with
-- their function types.
-- Data constructors are checked with type parameters in scope.
tcTypeDef :: TypeDef -> TypeCheckM ()
tcTypeDef (TypeDef typeName typeVars conDefs) =
  mapM_ (tcConDef typeName typeVars) conDefs

-- | Checks that constructor fields are correct (well-formed, well-kinded and
-- use types in scope).
-- Constructs a function type for the data constructor.
-- Adds the constructor with its type to the environment.
tcConDef :: TypeName -> [TypeVar] -> ConDef -> TypeCheckM ()
tcConDef typeName typeVars (ConDef conName conFields) = do
  whenM (isDataConDefined conName) $
    throwError $ ConAlreadyDefined conName
  mapM_ (checkTypeWithTypeVars $ Set.fromList typeVars) conFields
  let conResultType = tyAppFromList typeName typeVars
      conArrType = tyArrowFromList conResultType conFields
      conType = tyForAllFromList conArrType typeVars
  addDataCon conName conType typeName

-- | Checks that the type of the body is consistent with the specified function
-- type.
tcFunDef :: FunDef -> TypeCheckM ()
tcFunDef (FunDef funName funType bodyExpr) = do
  bodyType <- tcExpr bodyExpr
  unlessM (bodyType `alphaEq` funType) $
    throwError $ FunBodyIncorrectType funName funType bodyType

-- | Expression type checking.
-- Return a type of the expression.
tcExpr :: Expr -> TypeCheckM Type
tcExpr expr =
  case expr of
    LitE lit -> return $ typeOfLiteral lit

    VarE varBinder -> do
      let var = getBinderVar varBinder
      -- it can be both a local variable and a global function
      unlessM (isVarBound var) $
        throwError $ VarNotBound var
      varType <- getVarType var
      let binderType = getBinderType varBinder
      checkType binderType
      unlessM (binderType `alphaEq` varType) $
        throwError $ VarIncorrectType var varType binderType
      return varType

    LambdaE varBinder bodyExpr -> do
      let var = getBinderVar varBinder
      whenM (isVarBound var) $
        throwError $ VarShadowing var
      let varType = getBinderType varBinder
      checkType varType
      -- Extend local type environment with the variable introduced by the
      -- lambda.
      -- This is safe, since we ensure above that all variable and function
      -- names are distinct.
      -- Perform the type checking of the body in this extended environment.
      let localTypeEnv = addLocalVar var varType emptyLocalTypeEnv
      bodyType <- locallyWithEnv localTypeEnv (tcExpr bodyExpr)
      let lambdaType = tyArrowFromList bodyType [varType]
      return lambdaType

    AppE exprApp exprArg -> do
      appType <- tcExpr exprApp
      argType <- tcExpr exprArg
      case appType of
        TyArrow paramType resultType ->
          ifM (not <$> (argType `alphaEq` paramType))
            (throwError $ IncorrectFunArgType paramType argType)
            (return resultType)
        _ -> throwError $ NotFunctionType appType

    TypeLambdaE typeVar bodyExpr -> do
      -- it is important to check in all these places, since it can shadow a
      -- type, type alias or another type variable
      whenM (isTypeOrAliasDefined $ typeVarToTypeName typeVar) $
        throwError $ TypeVarShadowsType typeVar
      whenM (isTypeVarBound typeVar) $
        throwError $ TypeVarShadowsTypeVar typeVar
      -- Extend local type environment with the type variable introduced by the
      -- type lambda.
      -- This is safe, since we ensure that all type variables and type names
      -- in scope are distinct.
      -- Perform the type checking of the body in this extended environment.
      let localTypeEnv = addLocalTypeVar typeVar emptyLocalTypeEnv
      bodyType <- locallyWithEnv localTypeEnv (tcExpr bodyExpr)
      let tyLambdaType = tyForAllFromList bodyType [typeVar]
      return tyLambdaType

    TypeAppE exprApp typeArg -> do
      -- Type application can be performed only with forall on the left-hand
      -- side.
      -- We replace free occurences of the type variable bound by the forall
      -- inside its body with the right-hand side type.
      appType <- tcExpr exprApp
      case appType of
        TyForAll typeVar forallBodyType -> do
          checkType typeArg
          let resultType = (typeVar, typeArg) `substTypeIn` forallBodyType
          return resultType
        _ -> throwError $ NotForallTypeApp appType

    ConNameE conName conType -> do
      checkType conType
      unlessM (isDataConDefined conName) $
        throwError $ ConNotDefined conName
      dataConTypeInfo <- getDataConTypeInfo conName
      unlessM (conType `alphaEq` dcontiType dataConTypeInfo) $
        throwError $ ConIncorrectType conName (dcontiType dataConTypeInfo) conType
      return conType

    LetE varBinder bindExpr bodyExpr -> do
      let var = getBinderVar varBinder
          varType = getBinderType varBinder
      checkType varType
      bindExprType <- tcExpr bindExpr
      bindExprTm <-
        case bindExprType of
          TyApp (TyMonad tm) a -> do
            unlessM (a `alphaEq` varType) $
              throwError $ IncorrectExprType (TyApp (TyMonad tm) varType) bindExprType
            return tm
          _ -> throwError $ NotMonadicType bindExprType
      bodyType <-
        if (var /= Var "_")
          then do whenM (isVarBound var) $
                    throwError $ VarShadowing var
                  -- Extend local type environment with the variable introduced by the
                  -- bind.
                  -- This is safe, since we ensure above that all variable and function
                  -- names are distinct.
                  -- Perform the type checking of the body in this extended environment.
                  let localTypeEnv = addLocalVar var varType emptyLocalTypeEnv
                  locallyWithEnv localTypeEnv (tcExpr bodyExpr)
          else tcExpr bodyExpr
      case bodyType of
        TyApp (TyMonad bodyExprTm) bodyResultType -> do
          unlessM (compatibleMonadTypes bodyExprTm bindExprTm) $
            throwError $ IncorrectMonad bindExprTm bodyExprTm
          ifM (bindExprTm `hasMoreEffectsThan` bodyExprTm)
            (return $ TyApp (TyMonad bindExprTm) bodyResultType)
            (return $ TyApp (TyMonad bodyExprTm) bodyResultType)
        _ -> throwError $ NotMonadicType bodyType

    ReturnE tm retExpr -> do
      checkTypeM tm
      retExprType <- tcExpr retExpr
      return $ TyApp (TyMonad tm) retExprType

    LiftE e tm1 tm2 -> do
      checkTypeM tm1
      checkTypeM tm2
      unlessM (tm1 `isMonadSuffixOf` tm2) $
        throwError $ IncorrectLifting tm1 tm2
      eType <- tcExpr e
      return $ TyApp (TyMonad tm2) (getMonadResultType eType)

    TupleE tElems -> do
      elemTypes <- mapM tcExpr tElems
      return $ TyTuple elemTypes

